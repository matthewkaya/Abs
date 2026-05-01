# Task 017 — Stripe Live Setup + Customer Portal + İlk Müşteri Playbook

**Status:** READY (Worker)
**Tahmini süre:** 4-5 saat
**Bağımlı task'lar:** 011 (Checkout/Webhook/Refund), 012 (Setup wizard, email templates), 013 (Vault — Stripe secret'lar vault'ta), 014 (Update channel), 015 (Real metrics), 016 (Symbol/RAG/ML)
**Hedef sonuç:** Production feature parity'den sonra ürünleştirme aşamasının ilk taşı: Stripe altyapısını **gerçek müşteri kabul edebilecek seviyeye** taşı (idempotent webhook, customer portal, billing dashboard, live mode runbook + first customer playbook).

---

## 0. Bağlam (Worker — önce bu paragrafı oku)

011 görevinden gelen Stripe altyapısı **kod düzeyinde tam**: Checkout Session, webhook (`checkout.session.completed` + `charge.refunded` + `customer.subscription.deleted`), demo countdown, license gate. 013 vault Stripe secret'larını şifreliyor. 012 setup wizard refund/expiration email template'lerini tamamladı. **Eksik kalanlar production-ready paid customer onboarding için kritik:**

1. **Webhook idempotency** — Stripe aynı event'i birden fazla kez gönderebilir (network retry, replay). Şu an aynı `event.id` iki kez gelirse `checkout.session.completed` `License.jti` unique constraint'inde duplicate yakalar **ama** `charge.refunded` ikinci geliş `revoked_at != None` kontrolüyle yakalansa bile `revoked_at` **timestamp'i değişir** → audit log kirlilik. Race condition altında iki webhook eşzamanlı geldiğinde `License.revoked_at` race'i mümkün. Çözüm: `WebhookEvent` table — her event_id bir kez işlenir.
2. **Customer Portal yok** — Müşteri lisansını yönetemiyor (cancel, billing detail, invoice history). 011'de 013+'a ertelenmişti. Stripe Billing Portal Session ile self-service.
3. **Setup script live mode safeguard yok** — Aynı script test/live mode farkındalığı taşımıyor. Live mode'a geçişte yanlış key ile yanlış product oluşturma riski → metadata `mode: test|live` + `--dry-run` flag.
4. **MCP `billing_status` tool yok** — Panel Stripe SSE event'i license-status feed'inde tek satır gösteriyor (011 modul F); ama ne kadar gelir geldi, bu hafta kaç lisans verildi/iade edildi görünmüyor. Solo operatör için günlük kontrol paneli gerekli.
5. **Live mode runbook yok** — `docs/billing-runbook.md` yok. Stripe test → live geçiş, webhook secret rotate, dispute/chargeback handling, manual refund procedure dokümantasyonu eksik.
6. **First customer playbook yok** — Beta lisansı manuel üretme (manuel JWT generate yolu var ama dokümante edilmemiş), outreach script, waitlist email sequence eksik.

**Worker bu 6 eksiği kapatacak, 011'in test mock'larıyla aynı disiplinle live Stripe API'ye DOKUNMAYACAK.** Tüm yeni testler `monkeypatch` ile mock'lı. Live e2e doğrulaması `docs/billing-runbook.md` içinde **kullanıcı manuel adımları** olarak yer alacak.

---

## 1. Amaç (Definition of Done)

Bittiğinde:

- [ ] `WebhookEvent` table + `webhook_events` write-once idempotency (event.id PK)
- [ ] Webhook handler her event'i `WebhookEvent` ile guard ediyor; duplicate'ler 200 `{duplicate: true}` döner
- [ ] `POST /v1/billing/portal` — customer_email body, Stripe Customer Portal URL döner (no key → 503, customer not found → 404)
- [ ] `infra/scripts/setup_stripe_products.py` — `--mode test|live` (default test), `--dry-run`, mode-aware metadata (`metadata.mode = 'test'|'live'`)
- [ ] MCP tool `billing_status` — products + revenue (today/MTD/total) + license count by status (active, revoked, expired) + recent webhook events (last 10)
- [ ] `docs/billing-runbook.md` (~600 kelime) — test→live geçiş, webhook rotate, dispute, manual refund, common errors
- [ ] `docs/first-customer-playbook.md` (~800 kelime) — beta lisans üretme komutu, outreach scripts (LinkedIn/Twitter/HN), waitlist email sequence (3 email), success metrics
- [ ] 22 yeni test, hepsi yeşil (270 → 292)
- [ ] Tool count guard 102 → 103
- [ ] 5 smoke evidence dosyası `/tmp/abs-017-smoke/evidence/`
- [ ] 011-016 mevcut testler hâlâ yeşil (regression yok)
- [ ] Live Stripe API hiçbir testte çağrılmadı — `[REDACTED]` policy

---

## 2. Modüller

### Modul A — Webhook Event Idempotency

**Yeni dosya:** `core/backend/app/db/models.py` patch — `WebhookEvent` model ekle (mevcut `License` modelinin altına):

```python
class WebhookEvent(SQLModel, table=True):
    """Stripe webhook idempotency — event_id bir kez işlenir.

    Stripe aynı event'i retry'larda tekrar gönderebilir. Bu tablo
    'tam-kez-işle' garantisi sağlar: handler önce INSERT dener,
    UNIQUE constraint patlarsa duplicate olarak 200 döner.
    """
    __tablename__ = "webhook_events"

    event_id: str = Field(primary_key=True, max_length=64)
    event_type: str = Field(max_length=64, index=True)
    received_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    processed_at: Optional[datetime] = Field(default=None)
    license_jti: Optional[str] = Field(default=None, max_length=64, index=True)
    error: Optional[str] = Field(default=None, max_length=512)
```

**Yeni helper:** `core/backend/app/api/webhooks/idempotency.py` (~70 satır):

```python
"""Webhook idempotency guard — event_id bazlı tek-sefer-işleme."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.db.models import WebhookEvent


class DuplicateEventError(Exception):
    """Aynı event_id daha önce işlendi."""

    def __init__(self, event_id: str, license_jti: Optional[str] = None):
        self.event_id = event_id
        self.license_jti = license_jti


def claim_event(db: Session, event_id: str, event_type: str) -> WebhookEvent:
    """Event'i 'işleniyor' olarak claim et.

    INSERT dener; duplicate ise IntegrityError yakalar ve DuplicateEventError raise eder.
    Returns: yeni WebhookEvent row (caller `processed_at` ve `license_jti`'yi
    sonra set eder).
    """
    row = WebhookEvent(event_id=event_id, event_type=event_type)
    try:
        db.add(row)
        db.commit()
        db.refresh(row)
        return row
    except IntegrityError:
        db.rollback()
        existing = db.scalars(
            select(WebhookEvent).where(WebhookEvent.event_id == event_id)
        ).first()
        raise DuplicateEventError(
            event_id=event_id,
            license_jti=existing.license_jti if existing else None,
        )


def mark_processed(
    db: Session,
    row: WebhookEvent,
    license_jti: Optional[str] = None,
    error: Optional[str] = None,
) -> None:
    row.processed_at = datetime.now(timezone.utc)
    row.license_jti = license_jti
    row.error = error[:512] if error else None
    db.add(row)
    db.commit()
```

**Patch:** `core/backend/app/api/webhooks/stripe.py` — handler başında claim:

```python
# imza doğrulama bloğundan SONRA:
event_id = event.get("id") or ""
event_type = event["type"]

if event_id:
    try:
        evt_row = claim_event(db, event_id=event_id, event_type=event_type)
    except DuplicateEventError as dup:
        return {
            "status": "ok",
            "type": event_type,
            "duplicate": True,
            "event_id": dup.event_id,
            "license_jti": dup.license_jti,
        }
else:
    evt_row = None  # eski/test event'lerde id yoksa idempotency atla
```

Mevcut handler logic'i (`checkout.session.completed`, `charge.refunded`, `customer.subscription.deleted`) **olduğu gibi kalır**, yalnız `return` öncesi `mark_processed(db, evt_row, license_jti=...)` çağrılır:

```python
# checkout.session.completed sonunda:
if evt_row is not None:
    mark_processed(db, evt_row, license_jti=payload_dict["jti"])
return {"status": "ok", "jti": payload_dict["jti"]}

# refund/sub-deleted sonunda:
if evt_row is not None:
    mark_processed(db, evt_row, license_jti=license_row.jti)
return {...}

# 'ignored' branch sonunda:
if evt_row is not None:
    mark_processed(db, evt_row)  # license_jti=None
return {"status": "ignored", "type": event["type"]}
```

**Migration:** SQLModel `create_all` mevcut — `app/db/session.py::init_db` zaten boot'ta `SQLModel.metadata.create_all`. Yeni table boot'ta otomatik oluşur. Production'da live DB'de manuel `CREATE TABLE` gerekmez (SQLite + Alembic kullanmıyoruz; 022+'da gelir).

**Yeni test:** `core/backend/tests/test_webhook_idempotency.py` (5 test, ~140 satır):

```python
def test_duplicate_checkout_session_completed_returns_duplicate(client, db, monkeypatch):
    """Aynı event.id ile iki kez gelirse ikinci 200 + duplicate=True."""
    # Mock stripe.Webhook.construct_event her iki çağrıda aynı event döner
    event = _make_checkout_completed_event(event_id="evt_test_001")
    monkeypatch.setattr("stripe.Webhook.construct_event", lambda *a, **k: event)
    # 1. çağrı: işlenir
    r1 = client.post("/webhooks/stripe", content=b"{}", headers={"stripe-signature": "x"})
    assert r1.status_code == 200
    assert r1.json()["status"] == "ok"
    assert "jti" in r1.json()
    # 2. çağrı: duplicate
    r2 = client.post("/webhooks/stripe", content=b"{}", headers={"stripe-signature": "x"})
    assert r2.status_code == 200
    assert r2.json()["duplicate"] is True
    assert r2.json()["license_jti"] == r1.json()["jti"]


def test_duplicate_refund_does_not_overwrite_revoked_at(client, db, monkeypatch):
    """İkinci charge.refunded gelirse revoked_at değişmez."""
    # 1. checkout → license var
    # 2. 1. refund → revoked
    # 3. 2. refund (aynı event.id) → revoked_at ilk değerle aynı kalır

def test_two_different_event_ids_both_processed(client, db, monkeypatch):
    """Farklı event.id'li iki event ikisi de işlenir."""

def test_webhook_events_table_has_event_type_index(db):
    """`event_type` üzerinde index tanımlı (recent events query hızlı)."""

def test_claim_event_race_condition_safe(db):
    """Eşzamanlı iki claim_event aynı event_id ile → biri DuplicateEventError."""
```

**Regression:** `tests/test_stripe_webhook.py` 4 test + `tests/test_refund_handler.py` 3 test hâlâ yeşil olmalı (mevcut event.id'ler test fixture'larında unique olarak tanımlı).

---

### Modul B — Customer Portal Endpoint

**Yeni dosya:** `core/backend/app/api/billing_portal.py` (~75 satır):

```python
"""Stripe Customer Portal — müşteri self-service (lisans yönetimi, fatura, iade).

POST /v1/billing/portal
  body: {"customer_email": "x@y.com"}
  → {"portal_url": "https://billing.stripe.com/...", "expires_at": ISO8601}

Akış:
1. Email'i lisans DB'sinde ara (revoked_at IS NULL ilk match)
2. License.customer_id_stripe ile stripe.billing_portal.Session.create
3. Portal URL döner (Stripe varsayılan 1 saat geçerli)
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone, timedelta

import stripe
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr
from sqlmodel import Session, select

from app.config import settings
from app.db.models import License
from app.db.session import get_session

router = APIRouter(prefix="/v1/billing", tags=["billing"])
logger = logging.getLogger(__name__)


class PortalRequest(BaseModel):
    customer_email: EmailStr
    return_url: str = "https://abs.automatiabcn.com/"


class PortalResponse(BaseModel):
    portal_url: str
    expires_at: str


@router.post("/portal", response_model=PortalResponse)
async def create_portal(
    body: PortalRequest,
    db: Session = Depends(get_session),
) -> PortalResponse:
    if not settings.stripe_secret_key:
        raise HTTPException(status_code=503, detail="Stripe yapılandırılmadı")

    license_row = db.scalars(
        select(License)
        .where(License.customer_email == body.customer_email)
        .where(License.revoked_at.is_(None))  # type: ignore[union-attr]
    ).first()

    if license_row is None or not license_row.customer_id_stripe:
        raise HTTPException(
            status_code=404,
            detail="Aktif lisans bulunamadı veya Stripe customer ID eksik",
        )

    stripe.api_key = settings.stripe_secret_key
    try:
        portal = stripe.billing_portal.Session.create(
            customer=license_row.customer_id_stripe,
            return_url=body.return_url,
        )
    except stripe.error.StripeError as exc:
        logger.exception("portal session create failed: %s", exc)
        raise HTTPException(status_code=502, detail=f"Stripe error: {str(exc)[:200]}") from exc

    expires = datetime.now(timezone.utc) + timedelta(hours=1)
    url = getattr(portal, "url", None) or portal.get("url")
    if not url:
        raise HTTPException(status_code=502, detail="Stripe portal response invalid")

    return PortalResponse(portal_url=url, expires_at=expires.isoformat())
```

**Patch:** `app/main.py` — `billing_portal_router` register et.

**Yeni test:** `tests/test_billing_portal.py` (4 test, ~120 satır):

```python
def test_portal_no_stripe_key_returns_503(client, monkeypatch):
    monkeypatch.setattr(settings, "stripe_secret_key", "")
    r = client.post("/v1/billing/portal", json={"customer_email": "a@b.com"})
    assert r.status_code == 503

def test_portal_no_active_license_returns_404(client, db, monkeypatch):
    monkeypatch.setattr(settings, "stripe_secret_key", "sk_test_x")
    r = client.post("/v1/billing/portal", json={"customer_email": "missing@b.com"})
    assert r.status_code == 404

def test_portal_active_license_returns_url(client, db, monkeypatch):
    """Aktif lisans + Stripe API mock → portal URL."""
    # License row insert (revoked_at None, customer_id_stripe="cus_abc")
    # stripe.billing_portal.Session.create mock → {"url": "https://billing.stripe.com/test", ...}
    r = client.post("/v1/billing/portal", json={"customer_email": "a@b.com"})
    assert r.status_code == 200
    assert "billing.stripe.com" in r.json()["portal_url"]

def test_portal_revoked_license_returns_404(client, db, monkeypatch):
    """Lisans revoke edilmiş ise 404 (refund sonrası portal kapalı)."""
```

**Stripe API mock:** Worker `monkeypatch.setattr("stripe.billing_portal.Session.create", lambda **kw: types.SimpleNamespace(url="https://billing.stripe.com/test_xyz", id="bps_test"))` ile mock — live API çağrılmaz.

---

### Modul C — Setup Script Live Mode Safeguard

**Patch:** `infra/scripts/setup_stripe_products.py` — argparse ile `--mode test|live` + `--dry-run` flag:

```python
"""ABS Stripe Product/Price kurulum yardımcısı.

Kullanım:
  # Test mode (default, güvenli):
  python infra/scripts/setup_stripe_products.py --mode test

  # Live mode (production müşteri kabul):
  ABS_STRIPE_SECRET_KEY=sk_live_... python infra/scripts/setup_stripe_products.py --mode live

  # Dry-run (hiçbir API çağrısı yapmaz, sadece plan yazar):
  python infra/scripts/setup_stripe_products.py --mode test --dry-run

3 product oluşturur (varsa atlar):
  - ABS Self-Host       ($299)   metadata.sku=self-host metadata.mode=<mode>
  - ABS Team Pack 5     ($1196)  metadata.sku=team-5    metadata.mode=<mode>
  - ABS Team Pack 10    ($2093)  metadata.sku=team-10   metadata.mode=<mode>

Output: Price ID'leri stdout. Çıkan satırları .env'e elle yapıştır.

Idempotent: aynı (metadata.sku, metadata.mode) ile mevcut product+matching unit_amount price varsa atlar.

Live mode safeguard:
- --mode live verilmedi VE ABS_STRIPE_SECRET_KEY sk_live_ ile başlıyorsa → ABORT
- --mode live verildi VE ABS_STRIPE_SECRET_KEY sk_test_ ile başlıyorsa → ABORT
- --dry-run her iki mode'da Stripe API çağırmaz
"""

import argparse
import os
import sys
from typing import List, Dict


def _validate_key_mode(api_key: str, mode: str) -> None:
    if mode == "live" and not api_key.startswith("sk_live_"):
        print(
            "GUVENLIK: --mode live verildi ama ABS_STRIPE_SECRET_KEY 'sk_live_' ile başlamiyor. ABORT.",
            file=sys.stderr,
        )
        sys.exit(2)
    if mode == "test" and not api_key.startswith("sk_test_"):
        print(
            "GUVENLIK: --mode test verildi ama ABS_STRIPE_SECRET_KEY 'sk_test_' ile başlamiyor. ABORT.",
            file=sys.stderr,
        )
        sys.exit(2)


def main() -> int:
    parser = argparse.ArgumentParser(description="ABS Stripe Products bootstrap")
    parser.add_argument("--mode", choices=["test", "live"], default="test")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    api_key = os.environ.get("ABS_STRIPE_SECRET_KEY", "")
    if not api_key:
        print("ABS_STRIPE_SECRET_KEY env var gerekli", file=sys.stderr)
        return 1

    _validate_key_mode(api_key, args.mode)

    products: List[Dict] = [
        {"name": "ABS Self-Host",    "amount": 29900,  "metadata_sku": "self-host"},
        {"name": "ABS Team Pack 5",  "amount": 119600, "metadata_sku": "team-5"},
        {"name": "ABS Team Pack 10", "amount": 209300, "metadata_sku": "team-10"},
    ]

    if args.dry_run:
        print(f"# DRY RUN — mode={args.mode} — hiçbir API çağrısı yapılmayacak")
        for spec in products:
            env_name = "ABS_PRICE_" + spec["metadata_sku"].replace("-", "_").upper()
            print(f"# WOULD-CREATE {spec['name']} ${spec['amount']/100} → {env_name}=<price_id>")
        return 0

    import stripe
    stripe.api_key = api_key

    for spec in products:
        existing = stripe.Product.list(active=True, limit=100)
        found = next(
            (
                p
                for p in existing.data
                if (getattr(p, "metadata", None) or {}).get("sku") == spec["metadata_sku"]
                and (getattr(p, "metadata", None) or {}).get("mode") == args.mode
            ),
            None,
        )
        # ... rest aynı, yalnız Product.create + Price.create metadata'ya 'mode' ekle:
        product = found or stripe.Product.create(
            name=spec["name"],
            metadata={"sku": spec["metadata_sku"], "mode": args.mode},
        )
        # Price.create değişmedi
        # ...

    return 0
```

**Yeni test:** `tests/test_setup_stripe_products.py` (4 test, ~110 satır):

```python
def test_dry_run_no_stripe_call(monkeypatch, capsys):
    """--dry-run hiç stripe import etmez (subprocess ile py_compile + stdout kontrol)."""
    # subprocess.run([python, script, "--mode", "test", "--dry-run"], env={..., ABS_STRIPE_SECRET_KEY: "sk_test_x"})
    # stdout 'WOULD-CREATE' satırları içermeli, stderr boş

def test_mode_live_with_test_key_aborts():
    """--mode live + sk_test_ → exit code 2."""

def test_mode_test_with_live_key_aborts():
    """--mode test + sk_live_ → exit code 2 (yanlış key live mode'a yansımasın)."""

def test_no_key_env_returns_1():
    """ABS_STRIPE_SECRET_KEY yok → exit 1."""
```

**Regression:** `tests/test_pricing_sku_mapping.py` 3 test hâlâ yeşil (script SKU mapping'i değişmedi, sadece argparse + safeguard eklendi).

---

### Modul D — MCP Tool: `billing_status`

**Yeni dosya:** `core/backend/app/mcp/tools/billing_tools.py` (~95 satır, 1 tool):

```python
"""MCP tool: billing_status — Stripe + lisans + revenue özeti.

Solo operatör günlük 'durum' kontrolü için tek tool.

Output:
  {
    "stripe_configured": bool,
    "products": [{sku, name, price_usd, mode}],   # Stripe API + cached 5dk
    "revenue": {
      "today_usd": float,            # bugün checkout.session.completed toplam
      "mtd_usd": float,              # ay başından
      "total_usd": float,            # tüm zamanlar
    },
    "licenses": {
      "active": int,                 # revoked_at IS NULL AND expires_at > now
      "revoked": int,
      "expired": int,
    },
    "recent_events": [               # son 10 webhook event
      {event_id, event_type, received_at, license_jti}
    ]
  }
"""

import time
from datetime import datetime, timezone

from app.config import settings
from app.db.models import License, WebhookEvent
from app.db.session import get_session_sync
from sqlmodel import select


_PRODUCT_CACHE: dict = {"data": None, "ts": 0}
_PRODUCT_CACHE_TTL = 300  # 5 dk


def _get_products_cached() -> list[dict]:
    now = time.time()
    if _PRODUCT_CACHE["data"] and (now - _PRODUCT_CACHE["ts"] < _PRODUCT_CACHE_TTL):
        return _PRODUCT_CACHE["data"]
    if not settings.stripe_secret_key:
        return []
    import stripe
    stripe.api_key = settings.stripe_secret_key
    try:
        products = stripe.Product.list(active=True, limit=10)
        out = []
        for p in products.data:
            sku = (getattr(p, "metadata", None) or {}).get("sku", "?")
            mode = (getattr(p, "metadata", None) or {}).get("mode", "?")
            prices = stripe.Price.list(product=p.id, active=True, limit=1)
            amount = prices.data[0].unit_amount if prices.data else 0
            out.append({"sku": sku, "name": p.name, "price_usd": amount / 100, "mode": mode})
        _PRODUCT_CACHE["data"] = out
        _PRODUCT_CACHE["ts"] = now
        return out
    except Exception:
        return []


def _compute_revenue(db) -> dict:
    """checkout.session.completed event'lerinden revenue hesapla.

    `WebhookEvent.event_type == 'checkout.session.completed'` AND
    `processed_at NOT NULL` (revoke etmemişse). Refund'lar revenue'den DÜŞÜLMEZ
    (Stripe gross revenue gösterir, refund ayrı raporlanır).
    """
    from datetime import timedelta
    now = datetime.now(timezone.utc)
    today_start = datetime(now.year, now.month, now.day, tzinfo=timezone.utc)
    mtd_start = datetime(now.year, now.month, 1, tzinfo=timezone.utc)

    # License tier × seat_count × tier price → her lisansın tutarı
    PRICE_MAP = {("self-host", 1): 299, ("team", 5): 1196, ("team", 10): 2093}
    licenses = db.scalars(select(License)).all()

    today_usd = 0.0
    mtd_usd = 0.0
    total_usd = 0.0
    for lic in licenses:
        amount = PRICE_MAP.get((lic.tier, lic.seat_count), 0)
        total_usd += amount
        if lic.issued_at >= mtd_start:
            mtd_usd += amount
        if lic.issued_at >= today_start:
            today_usd += amount
    return {"today_usd": today_usd, "mtd_usd": mtd_usd, "total_usd": total_usd}


def _license_counts(db) -> dict:
    now = datetime.now(timezone.utc)
    licenses = db.scalars(select(License)).all()
    active = sum(1 for lic in licenses if lic.revoked_at is None and lic.expires_at > now)
    revoked = sum(1 for lic in licenses if lic.revoked_at is not None)
    expired = sum(1 for lic in licenses if lic.revoked_at is None and lic.expires_at <= now)
    return {"active": active, "revoked": revoked, "expired": expired}


def _recent_events(db, limit: int = 10) -> list[dict]:
    rows = db.scalars(
        select(WebhookEvent).order_by(WebhookEvent.received_at.desc()).limit(limit)
    ).all()
    return [
        {
            "event_id": r.event_id,
            "event_type": r.event_type,
            "received_at": r.received_at.isoformat(),
            "license_jti": r.license_jti,
        }
        for r in rows
    ]


async def billing_status() -> dict:
    """ABS billing dashboard — Stripe + DB lisans + son 10 webhook."""
    with get_session_sync() as db:
        return {
            "stripe_configured": bool(settings.stripe_secret_key),
            "products": _get_products_cached(),
            "revenue": _compute_revenue(db),
            "licenses": _license_counts(db),
            "recent_events": _recent_events(db),
        }
```

**Patch:** `app/mcp/server.py` — `billing_tools.billing_status` register et + count 102 → 103.

**Patch:** `app/db/session.py` — `get_session_sync()` context manager ekle (DB sync session — MCP tool async ama DB query sync; `with` ile kapanır).

**Yeni test:** `tests/test_billing_status_mcp.py` (3 test, ~100 satır):

```python
def test_billing_status_no_stripe_returns_empty_products(monkeypatch):
    monkeypatch.setattr(settings, "stripe_secret_key", "")
    out = asyncio.run(billing_status())
    assert out["stripe_configured"] is False
    assert out["products"] == []

def test_billing_status_revenue_aggregation(db, monkeypatch):
    """3 lisans (self-host + team-5 + team-10) → total_usd = 299 + 1196 + 2093."""

def test_billing_status_recent_events_ordered_desc(db):
    """WebhookEvent insert order ↓ — son 10 newest-first döner."""
```

**Tool count guard:** `tests/test_tools_count.py` 102 → **103**, must_have: `billing_status`.

---

### Modul E — Live Mode Runbook (`docs/billing-runbook.md`)

**İçerik (yaklaşık 600 kelime, kullanıcı manuel adımları):**

```markdown
# Stripe Billing Runbook

Bu doküman ABS billing altyapısını canlıya alma + günlük operasyon sorumluluklarını
tanımlar. Hedef kitle: solo operatör (Enes / Automatia BCN).

## 1. Test Mode → Live Mode Geçişi

### 1.1 Stripe Dashboard hazırlık
1. Stripe Dashboard → Developers → API keys → "Live mode" toggle
2. `Reveal live key` → `sk_live_...` kopyala (TEK SEFER GÖRÜNÜR)
3. `Webhooks` → "+ Add endpoint" → URL `https://abs.automatiabcn.com/webhooks/stripe`
   - Events: `checkout.session.completed`, `charge.refunded`,
     `customer.subscription.deleted`
   - Signing secret kopyala (`whsec_...`)

### 1.2 Vault'a yaz
```bash
# Vault aktif (013), plaintext .env'e ASLA yazma
ssh prod-server
cd /opt/abs
sops --age=$(cat /app/vault-key/age.pub) -e -i secrets/billing.enc.json
# Editör açılır, ABS_STRIPE_SECRET_KEY ve ABS_STRIPE_WEBHOOK_SECRET güncelle
docker compose restart abs-backend
```

### 1.3 Live products oluştur
```bash
ABS_STRIPE_SECRET_KEY=sk_live_... \
  python infra/scripts/setup_stripe_products.py --mode live
# Çıkan ABS_PRICE_*=price_... satırlarını vault'a yaz
```

### 1.4 İlk live test
1. `https://abs.automatiabcn.com/` → kendi email'inle "Buy Self-Host"
2. Test kart YERİNE gerçek kart kullanılır (live mode test kart kabul etmez)
3. Stripe Dashboard → Payments → ödeme görüldü mü?
4. Email gelir → license key
5. Setup wizard'a gir → activate → `mcp_require_license` toggle aç → MCP tool çalışır

### 1.5 İlk live test'ten sonra
- Kendi ödemeyi `Stripe Dashboard → Refund` ile geri al (test maliyeti $299 değil $0 olur)
- Webhook event log'u kontrol et: `select(WebhookEvent).order_by(received_at.desc())`
- Refund webhook geldi mi? `License.revoked_at` doldu mu?

## 2. Webhook Secret Rotate

Compromise şüphesi varsa:
1. Stripe Dashboard → Webhooks → mevcut endpoint → `Roll secret`
2. Yeni `whsec_...` vault'a yaz
3. Backend restart
4. `Send test webhook` ile doğrula (Stripe Dashboard'dan)

## 3. Manual Refund (müşteri talebi)

Stripe Dashboard üzerinden yapılır:
1. Payments → ilgili ödeme → "Refund payment"
2. Reason: customer_request | duplicate | fraudulent
3. Webhook otomatik tetiklenir → `License.revoked_at` set olur
4. Refund email gönderilir (template: `license_refund.html`)

## 4. Dispute / Chargeback

Stripe email gelir: "A dispute was opened on your charge."
1. Dashboard → Disputes → ilgili kayıt
2. Evidence yükle: license_delivery email screenshot, customer activate log
3. Backend'de `License.revoked_at` MANUEL set et (chargeback ödeme alıkonur):
   ```python
   docker compose exec abs-backend python -c "
   from app.db.session import get_session_sync
   from app.db.models import License
   with get_session_sync() as db:
       lic = db.scalars(select(License).where(License.customer_email=='X')).first()
       lic.revoked_at = datetime.now(timezone.utc)
       lic.revoked_reason = 'stripe_chargeback'
       db.commit()
   "
   ```

## 5. Yaygın Hatalar

| Hata | Sebep | Çözüm |
|---|---|---|
| `503 Stripe yapılandırılmadı` | env yok | vault decrypt + restart |
| `400 İmza doğrulanamadı` | webhook secret yanlış | endpoint secret rotate, vault güncelle |
| `502 Stripe error: rate_limited` | API rate limit | exponential backoff, 30s sonra retry |
| `400 Payload geçersiz` | Stripe SDK version mismatch | `pip install -U stripe` |
| Refund webhook gelmiyor | Endpoint events list eksik | Dashboard → Webhooks → Events ekle |

## 6. Günlük İzleme

```bash
# MCP tool ile
ask "billing_status" gptoss

# DB direct
sqlite3 /app/data/abs.db "SELECT event_type, COUNT(*) FROM webhook_events GROUP BY event_type"
```

Anormal pattern:
- `charge.refunded > 5%` → ürün/ödeme akışı sorunu, müşteri retention
- `license.revoked_at` ortalama < 7 gün → demo/onboarding sorunu
- `webhook_events.error NOT NULL` → handler bug, log incele
```

---

### Modul F — First Customer Playbook (`docs/first-customer-playbook.md`)

**İçerik (~800 kelime):**

```markdown
# First Customer Playbook

Hedef: ABS'nin **ilk 3 ücretli müşterisi** + **5 beta lisansı**. Solo operatör için
12 haftalık taktik playbook (sprint formatı).

## Faz 1 — Beta Lisansları (Hafta 1-2)

### 1.1 Beta lisans manuel üretme
```python
# Production server'da:
docker compose exec abs-backend python -c "
from app.licensing import generate_license, verify_license
token = generate_license(
    customer_id='beta:enes-friend-1',
    tier='self-host',
    seat_count=1,
    duration_days=180,  # 6 ay beta
)
print(token)
"
```

DB'ye License row ekle (manuel `customer_email`, `customer_id_stripe=''`).
Email gönder: `send_license_email(to=..., license_key=token, refund_url='')`.

### 1.2 Beta hedef listesi (5 kişi)
- 2x Türkiye CTO (LinkedIn network)
- 2x ES/EU indie hacker (Twitter dev community)
- 1x kişisel kullanım — Enes kendi (dogfood doğrulama)

### 1.3 Beta feedback toplama
- Slack channel veya Discord (özel)
- Haftalık 30dk video call
- Bug report → GitHub issues

## Faz 2 — Landing + Outreach (Hafta 3-4)

### 2.1 Landing page eksikleri (017 sonrası 018'e)
- Hero CTA "Start Free Trial" → demo countdown
- Pricing table (3 SKU, /year vs /one-time vurgu)
- Social proof (beta tester quotes, screenshot)
- FAQ — "Anthropic TOS uygun mu?", "Vault nasıl çalışır?", "Veri Anthropic'e gider mi?"

### 2.2 Outreach Scripts

**LinkedIn (CTO 10-50 kişilik firma) — ilk mesaj:**
```
Merhaba [İsim],

Automatia ABS'in kurucusuyum — Claude Code'u extend eden self-host bir orchestrator
geliştirdik. 75 MCP tool + 6 provider cascade + RAG hybrid + Türkçe quality pipeline.

Ekibinizde 10+ developer Claude kullanıyorsa, $20 plan + ABS = $200 Max plan kalitesi
elde ediyorsunuz. ROI: 10 kişilik ekip → $1300/ay tasarruf.

Demo (15 dk) için müsait misiniz?

—Enes
```

**Twitter/X (build-in-public):**
```
🚀 ABS v1.0 launch:
• Self-host AI orchestration for Claude Code
• 75 MCP tools + 6 providers (Groq/Cerebras/Gemini/CF/Cohere)
• 14-day free demo, $299 self-host
• Open core (Apache 2.0 backend)

Demo: abs.automatiabcn.com/demo
```

**HN Show:**
```
Title: Show HN: Automatia ABS — self-host orchestration for Claude Code ($299)

Body:
I built ABS over 6 months to extend my $20 Claude Pro plan with multi-provider routing
(Groq/Cerebras/Gemini), RAG, and Turkish quality pipelines. After dogfooding daily I
decided to release.

Tech: FastAPI + SQLite + sops/age vault + Docker. 75 MCP tools, 102 endpoints.
Privacy: customer code never leaves their server (only Claude prompts go to Anthropic
— transparent in FAQ).

Demo: abs.automatiabcn.com
Repo: github.com/automatiabcn/abs (Apache 2.0 core)

Happy to answer questions.
```

### 2.3 Waitlist email sequence

**Email 1 — Welcome (signup +0h):**
- Konu: "Welcome to ABS waitlist — what you get"
- Açıklama: ABS nedir, ne çözer, beta lisans erken erişim
- CTA: Twitter follow + roadmap link

**Email 2 — Demo screencast (signup +3 gün):**
- Konu: "ABS in action — 3-min demo"
- 3 dakikalık Loom: setup wizard + Claude Code tool çağrı + panel
- CTA: "Reply with your use case for a custom demo"

**Email 3 — Launch (signup +7 gün, launch günü):**
- Konu: "ABS is live — first 50 customers get 50% off"
- Indirim kodu (FIRST50 → Stripe coupon, manuel oluştur)
- CTA: "Start free 14-day trial"

## Faz 3 — Launch Day (Hafta 5)

### 3.1 Launch checklist
- [ ] Landing page premium SVG illustrations (017 — 018'e)
- [ ] Stripe live products + webhook live (017 §1)
- [ ] HN Show post taslağı hazır (1-2 saat içinde post)
- [ ] Twitter thread (8 tweet, dogfooding süreci)
- [ ] Indie Hacker post
- [ ] r/selfhosted post (ALLOWED, dikkatli wording)

### 3.2 Launch günü zaman çizelgesi (UTC)
- 12:00 — HN Show post (peak EU/US overlap)
- 12:15 — Twitter thread + tag relevant accounts
- 12:30 — Indie Hacker
- 13:00 — Reddit r/selfhosted + r/ClaudeAI
- 14:00 — Email sequence email 3 trigger
- Akşam — yorumları yanıtla (HN/Reddit)

## Faz 4 — Post-Launch İzleme (Hafta 6+)

### 4.1 Success metrics
| Metrik | Hedef (ay 1) | Hedef (ay 3) |
|---|---|---|
| Waitlist signup | 200 | 1000 |
| Demo başlatma | 50 | 250 |
| Lisans satışı | 3 | 15 |
| MRR | $897 | $4485 (+team packs) |
| Churn (refund) | <5% | <3% |

### 4.2 Haftalık operasyon (15dk/gün)
1. `billing_status` MCP tool çağrısı → revenue + license + recent events
2. Refund/dispute varsa § Runbook 3-4 izle
3. Beta tester slack ping: feedback?
4. GitHub issues triaj

### 4.3 Aylık retro
- Refund nedenleri çıkar
- Demo bırakma noktasını bul (setup wizard adım metrikleri — 022+'a)
- Churn olan müşteri ile 30dk debrief
```

---

## 3. Test Stratejisi

| Dosya | Test | Açıklama |
|---|---|---|
| `test_webhook_idempotency.py` | 5 | Duplicate event, race, index, refund overwrite |
| `test_billing_portal.py` | 4 | 503/404 paths, mock Stripe portal session |
| `test_setup_stripe_products.py` | 4 | dry-run, mode×key safeguard, env eksik |
| `test_billing_status_mcp.py` | 3 | Empty products, revenue aggregation, recent ordering |
| `test_tools_count.py` | 1 | 103 + must_have billing_status |
| `test_runbook_doc_exists.py` | 2 | docs/billing-runbook.md + first-customer-playbook.md var, min 500 kelime |
| `test_webhook_event_model.py` | 3 | SQLModel table schema, index, FK yok |
| **TOPLAM** | **22** | (270 → 292) |

**Mock kuralı (kritik):** Live Stripe API hiçbir testte çağrılmaz. `monkeypatch.setattr("stripe.checkout.Session.create", ...)`, `monkeypatch.setattr("stripe.Webhook.construct_event", ...)`, `monkeypatch.setattr("stripe.billing_portal.Session.create", ...)`, `monkeypatch.setattr("stripe.Product.list", ...)`, `monkeypatch.setattr("stripe.Price.list", ...)`. Bu bilgiyi 011'den miras al.

**Regression kontrol komutu:**
```bash
.venv/bin/pytest -q tests/test_stripe_webhook.py tests/test_refund_handler.py tests/test_pricing_sku_mapping.py tests/test_checkout_session.py tests/test_demo_mode.py tests/test_license_gate.py
```
**Beklenen:** 22/22 PASS (011'den miras).

---

## 4. Smoke Evidence (`/tmp/abs-017-smoke/evidence/`)

5 dosya, hepsi mock'lı (live Stripe çağrılmaz):

1. **`01_webhook_idempotency.json`** — Aynı event_id ile iki POST, ikincisi `{duplicate: true}`. Backend log'tan veya direct httpx call sonucu.
2. **`02_billing_portal.json`** — `POST /v1/billing/portal` mock'lu Stripe response → portal_url + expires_at.
3. **`03_setup_script_dry_run.txt`** — `python infra/scripts/setup_stripe_products.py --mode test --dry-run` stdout (3 WOULD-CREATE satırı).
4. **`04_billing_status_mcp.json`** — `billing_status` tool response (mock products + 2 license + recent_events).
5. **`05_setup_script_safeguard.txt`** — `--mode live + sk_test_` ABORT exit code 2 stderr çıktısı.

Her dosya `evidence/` altına yaz, son adım hepsini doğrula:
```bash
ls /tmp/abs-017-smoke/evidence/ && \
  for f in /tmp/abs-017-smoke/evidence/*.json; do python -c "import json; json.load(open('$f'))"; done
```

---

## 5. Adım Adım (Worker İçin)

```
1.  git status (clean baseline) + .venv/bin/pytest -q (270 PASS doğrula)
2.  Modul A — WebhookEvent model + idempotency.py + webhook patch
3.    Test: test_webhook_idempotency.py (5 test) — yaz, çalıştır, yeşil olana kadar düzelt
4.    Regression: test_stripe_webhook.py + test_refund_handler.py hâlâ yeşil
5.  Modul B — billing_portal.py + main.py register
6.    Test: test_billing_portal.py (4 test)
7.  Modul C — setup_stripe_products.py argparse refactor
8.    Test: test_setup_stripe_products.py (4 test, subprocess mock)
9.    Regression: test_pricing_sku_mapping.py 3/3
10. Modul D — billing_tools.py + server.py register + get_session_sync ekle
11.   Test: test_billing_status_mcp.py (3 test) + test_tools_count.py 102→103
12. Modul E — docs/billing-runbook.md (~600 kelime, qwen32b ile yazdırılabilir)
13. Modul F — docs/first-customer-playbook.md (~800 kelime, qwen32b)
14.   Test: test_runbook_doc_exists.py (2 test) + test_webhook_event_model.py (3)
15. Smoke: 5 evidence dosyası /tmp/abs-017-smoke/evidence/
16. Final verify: pytest -q (292 PASS), tool count 103, evidence 5/5
17. Task summary yaz: 017-stripe-live-customer-playbook-summary.md
18. Klasör taşı: _agent-tasks/017-*.md → _agent-tasks/completed/
```

**Backward compat:** Mevcut 011-016 davranışı asla bozulmaz. Yeni `WebhookEvent` table boot'ta yaratılır (SQLModel create_all idempotent). Mevcut License rows'a dokunulmaz. `mcp_require_license` default False kalır. Setup script default `--mode test` (geri uyumlu).

**Rollback senaryosu:** Modul A bozulursa `WebhookEvent` table'ını sil, `webhook_events` tablo referanslarını kaldır, webhook handler 011 versiyonuna dön. Test'lerden 5 idempotency testi sil.

---

## 6. Worker Notları (Kritik)

1. **Live Stripe API'ye DOKUNMA.** Tüm test+smoke mock. `ABS_STRIPE_SECRET_KEY` .env'de varsa bile testlerde override et: `monkeypatch.setattr(settings, "stripe_secret_key", "sk_test_dummy")`.
2. **`[REDACTED]` policy** — Summary'de Stripe key kısmını "Stripe secret + webhook secret `ABS_STRIPE_SECRET_KEY` / `ABS_STRIPE_WEBHOOK_SECRET` env'den okundu — [REDACTED]" formatında yaz (011 örneği).
3. **`get_session_sync` yeni** — `app/db/session.py` içinde async `get_session` zaten var. Sync versiyon MCP tool için gerek (MCP tool async ama DB query sync; `with get_session_sync() as db: ...` pattern). Yoksa ekle.
4. **`docs/billing-runbook.md` ve `first-customer-playbook.md`** — qwen32b veya gptoss ile yazdırılabilir (`ask "..." qwen32b`), ama format spec'e uygun olmalı (markdown başlıkları, kod blokları). Worker dilerse kendi yazar.
5. **Stripe coupon (`FIRST50`)** — first-customer-playbook'ta bahsedilen indirim kodu **Stripe Dashboard'dan manuel** oluşturulur (kod tarafı 022+'a). Playbook'ta sadece pattern göster.
6. **`charge.refunded` revenue düşmez** — `_compute_revenue` Gross revenue gösterir (Stripe Dashboard ile aynı). Net revenue hesaplaması 022+'a (refund subtraction + Stripe fees).
7. **Time zone** — Tüm `datetime.now()` çağrıları `tz=timezone.utc`. `today_start` UTC midnight (TR/ES farkı önemsiz, audit log için global).
8. **WebhookEvent retention** — Şu an silmiyor. Production'da 90 gün sonra purge cron 022+'a planlanır. Şimdilik tablo büyür ama event_id PK sayesinde lookup hızlı.
9. **`metadata.license_jti` checkout flow'da** — 011 modul D notu: webhook frontend'inde `metadata.license_jti` zorunlu kılınması 014'ten sonra deferred. 017'de **zorunlu kılınmıyor** çünkü ilk müşteriler için metadata akışı netleşmemiş; refund flow `customer_id_stripe` fallback ile çalışıyor. 022+'da adresleyebilir.
10. **Demo countdown reset** — Live mode'a geçişte mevcut demo state'leri etkilenmez (her self-host kurulum kendi `data_dir/demo_state.json` taşır). Customer support ihtiyacı olursa runbook'a "demo manuel reset" prosedürü eklenebilir (022+).

---

## 7. Definition of Done — Kontrol Listesi

```
[ ] WebhookEvent model + migration (boot create_all)
[ ] idempotency.py + webhook patch + 5 test yeşil
[ ] billing_portal.py + 4 test yeşil
[ ] setup_stripe_products.py argparse refactor + 4 test yeşil
[ ] billing_tools.py + tool register + 3 test + count 103
[ ] docs/billing-runbook.md (≥500 kelime, ≥6 ana bölüm)
[ ] docs/first-customer-playbook.md (≥600 kelime, ≥4 faz)
[ ] test_runbook_doc_exists.py 2 test + test_webhook_event_model.py 3 test
[ ] pytest -q → 292 passed (270 + 22)
[ ] tool count 103, must_have billing_status
[ ] /tmp/abs-017-smoke/evidence/ → 5 dosya, hepsi valid (JSON parse + txt readable)
[ ] 011-016 mevcut testler hâlâ yeşil (regresyon yok)
[ ] 017-stripe-live-customer-playbook-summary.md yazıldı
[ ] Task _agent-tasks/completed/'a taşındı
[ ] Stripe live API çağrısı yapılmadı (grep'le doğrula: tests'te `sk_live_` yok)
```
