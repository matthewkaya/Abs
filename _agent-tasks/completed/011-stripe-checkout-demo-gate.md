# Task 011 — Checkout Session + Demo Mode + License Gate + Refund + Pricing

**Tahmini süre:** 3-4 saat (mevcut Stripe altyapısı üzerine 7 eksik modül)
**Önkoşul:** 010 tamam (89 MCP tool, 137/137 pytest yeşil)

## Bağlam

006-009 boyunca **JWT lisans altyapısı + Stripe webhook + activate endpoint + email sender** yazıldı. Mevcut çalışan parçalar:

- ✅ `app/licensing/{generator,verifier,keys,schemas}.py` — RS256 JWT
- ✅ `app/api/webhooks/stripe.py` — `checkout.session.completed` handler tam
- ✅ `app/api/license.py` — `POST /v1/license/activate`, `GET /v1/license/status`
- ✅ `app/db/models.py::License` — `revoked_at`/`revoked_reason` kolonları (refund destekli)
- ✅ `app/email/sender.py` — SMTP veya console fallback
- ✅ 11 test (`test_stripe_webhook.py` 4 + `test_license_api.py` 3 + `test_licensing.py` 4)
- ✅ `config.py` — `stripe_secret_key`, `stripe_webhook_secret`, `mcp_require_license` (default False)

011 **eksik 7 parçayı** tamamlar — sıfırdan yazım YOK, mevcut üzerine inşa:

1. **Checkout session creation** (`POST /v1/checkout/create-session`) — landing page "Buy" → Stripe Checkout URL döndür
2. **Demo mode** — kurulumdan sonra 14 gün full feature, dolunca MCP+panel kapanır
3. **License/demo gate** — `mcp_require_license=True` ise her MCP tool çağrısında enforcement
4. **Refund handler** — `charge.refunded` ve `customer.subscription.deleted` webhook event → license revoke
5. **Pricing config** — Stripe Price ID'leri config-driven (`self-host` $299, `team-5` $1196, `team-10` $2093)
6. **Panel demo countdown** — SSE `license-status` event + banner UX
7. **MCP tools** — `license_status` + `demo_status` (Claude Code'dan sorgulanabilir)

**Tool sayısı hedefi:** 89 → **91 tool** (+2: `license_status`, `demo_status`).
**Test sayısı hedefi:** 137 → **~155+ test** (+18: 4 checkout, 5 demo, 4 gate, 3 refund, 2 pricing).

## ⚠️ STRIPE API KEY KURALI

Kullanıcı (Enes) **mevcut Automatia BCN Stripe hesabını** kullanacak. Worker:

- ❌ **Yeni Stripe key oluşturmasın** (sandbox veya prod)
- ✅ Mevcut env var'ları kullansın: `ABS_STRIPE_SECRET_KEY` + `ABS_STRIPE_WEBHOOK_SECRET`
- ✅ Live test için key'leri **kullanıcıdan** istesin (terminal prompt veya `.env.local` referansı). Anahtarı **task summary.md'ye yazma** — sadece `[REDACTED]` veya "set in .env.local" yaz.
- ✅ Stripe Product/Price ID'leri Stripe Dashboard'dan kullanıcı verecek; kod config'den okusun (`abs_price_self_host`, `abs_price_team_5`, `abs_price_team_10` env var).
- ✅ Test ortamında: `pyttest` ile her Stripe API çağrısı **mock** (respx veya `stripe._client_factory`). Live API çağrısı testte YOK.

## Giriş (Mevcut Durum — Worker doğrulasın)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                          # 137 passed
.venv/bin/pytest tests/test_stripe_webhook.py tests/test_license_api.py tests/test_licensing.py -v
# 11 passed
.venv/bin/python -c "from app.config import settings; print('stripe_key set:', bool(settings.stripe_secret_key))"
# stripe_key set: False (test ortamı; gerçek key sadece prod .env'de)
```

## Beklenen Çıktı

### A. Checkout Session Endpoint

**Yeni dosya** `app/api/checkout.py` (~110 satır):

```python
"""Stripe Checkout Session creation — landing page'den çağrılır.

POST /v1/checkout/create-session
  body: {"sku": "self-host" | "team-5" | "team-10", "customer_email": "x@y.com"}
  → {"checkout_url": "https://checkout.stripe.com/...", "session_id": "cs_..."}

Stripe Price ID'leri config'den (`abs_price_self_host`, `abs_price_team_5`, `abs_price_team_10`).
"""
from __future__ import annotations
import logging
from typing import Literal
import stripe
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from app.config import settings

router = APIRouter(prefix="/v1/checkout", tags=["checkout"])
logger = logging.getLogger(__name__)

stripe.api_key = settings.stripe_secret_key

_SKU_TO_PRICE = {
    "self-host": (lambda: settings.abs_price_self_host, 1),
    "team-5": (lambda: settings.abs_price_team_5, 5),
    "team-10": (lambda: settings.abs_price_team_10, 10),
}

class CreateSessionRequest(BaseModel):
    sku: Literal["self-host", "team-5", "team-10"] = "self-host"
    customer_email: EmailStr
    success_url: str = Field(default="https://abs.automatiabcn.com/thanks")
    cancel_url: str = Field(default="https://abs.automatiabcn.com/")

class CreateSessionResponse(BaseModel):
    checkout_url: str
    session_id: str

@router.post("/create-session", response_model=CreateSessionResponse)
async def create_session(body: CreateSessionRequest) -> CreateSessionResponse:
    if not settings.stripe_secret_key:
        raise HTTPException(status_code=503, detail="Stripe yapılandırılmadı")
    price_resolver, seat_count = _SKU_TO_PRICE[body.sku]
    price_id = price_resolver()
    if not price_id:
        raise HTTPException(status_code=503, detail=f"Price ID yapılandırılmadı: {body.sku}")
    try:
        session = stripe.checkout.Session.create(
            mode="payment",
            payment_method_types=["card"],
            line_items=[{"price": price_id, "quantity": 1}],
            customer_email=body.customer_email,
            success_url=body.success_url,
            cancel_url=body.cancel_url,
            metadata={"tier": "self-host" if body.sku == "self-host" else "team",
                      "seat_count": str(seat_count), "sku": body.sku},
        )
    except stripe.error.StripeError as exc:
        logger.exception("checkout session create failed: %s", exc)
        raise HTTPException(status_code=502, detail=f"Stripe error: {exc.user_message or str(exc)}")
    return CreateSessionResponse(checkout_url=session.url, session_id=session.id)
```

**Patch** `app/main.py`:
```python
from app.api import checkout as checkout_router
# ...
app.include_router(checkout_router.router)
```

**Patch** `app/config.py`:
```python
abs_price_self_host: str = ""   # Stripe Price ID — $299 self-host
abs_price_team_5: str = ""      # Stripe Price ID — $1196 team-pack 5 seat
abs_price_team_10: str = ""     # Stripe Price ID — $2093 team-pack 10 seat
```

**Test** `tests/test_checkout_session.py` (~110 satır, 4 test):

1. `test_create_session_no_stripe_key_503`: `monkeypatch settings.stripe_secret_key=""` → 503.
2. `test_create_session_no_price_id_503`: stripe_secret_key set ama `abs_price_self_host=""` → 503.
3. `test_create_session_invalid_sku_422`: `body={"sku":"foo","customer_email":"a@b.c"}` → 422 (Pydantic Literal).
4. `test_create_session_returns_url`: monkeypatch `stripe.checkout.Session.create` → mock obj `{url:"https://x", id:"cs_test"}` → 200 + body.

### B. Demo Mode + 14-Day Countdown

**Yeni dosya** `app/licensing/demo.py` (~110 satır):

```python
"""Demo mode — kurulumdan sonra 14 gün full feature, dolunca expired.

Demo state file: {data_dir}/demo_state.json
  {"started_at": <unix ts>, "expires_at": <unix ts>, "duration_days": 14}

Lisans aktive edilince demo iptal olur (`is_active()` False döner).
"""
from __future__ import annotations
import json
import time
from pathlib import Path
from typing import Dict, Optional
from app.config import settings

DEMO_DURATION_DAYS = 14

def _state_path() -> Path:
    p = Path(settings.data_dir) / "demo_state.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p

def start_demo() -> Dict:
    """Demo zaten başlatılmadıysa başlat. Idempotent."""
    p = _state_path()
    if p.is_file():
        return _read_state()
    now = time.time()
    state = {
        "started_at": now,
        "expires_at": now + DEMO_DURATION_DAYS * 86400,
        "duration_days": DEMO_DURATION_DAYS,
    }
    p.write_text(json.dumps(state), encoding="utf-8")
    return state

def _read_state() -> Optional[Dict]:
    p = _state_path()
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return None

def status() -> Dict:
    """Demo durum snapshot."""
    state = _read_state()
    if not state:
        return {"started": False, "active": False, "expired": False,
                "days_remaining": None, "started_at": None, "expires_at": None}
    now = time.time()
    expired = now >= state["expires_at"]
    days_remaining = max(0, int((state["expires_at"] - now) / 86400))
    return {
        "started": True,
        "active": not expired,
        "expired": expired,
        "days_remaining": days_remaining,
        "started_at": state["started_at"],
        "expires_at": state["expires_at"],
    }

def is_active() -> bool:
    """Lisans yoksa demo aktif mi?"""
    if settings.license_key:
        return False  # lisans varsa demo bypassed
    s = status()
    return s["active"]

def reset() -> None:
    """Demo state sil — ilk kurulum reset (test/dev)."""
    p = _state_path()
    if p.is_file():
        p.unlink()
```

**Patch** `app/main.py`: `lifespan` içinde `start_demo()` çağrısı (lisans yoksa demo başlat):

```python
@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_db()
    # 011 — lisans yoksa demo başlat (idempotent)
    if not settings.license_key:
        from app.licensing.demo import start_demo
        try:
            start_demo()
        except Exception:
            pass
    # ... mevcut MCP session manager
```

**Patch** `app/api/license.py` — yeni endpoint `GET /v1/license/demo-status`:
```python
@router.get("/demo-status")
async def demo_status_endpoint() -> Dict[str, Any]:
    from app.licensing.demo import status
    return status()
```

**Test** `tests/test_demo_mode.py` (~140 satır, 5 test):

1. `test_start_demo_writes_state`: tmp_path → `start_demo()` → file var, `started_at` valid.
2. `test_start_demo_idempotent`: 2 kere çağır → aynı `started_at`.
3. `test_status_active_within_14_days`: `start_demo()` → `status()["active"]==True`, `days_remaining<=14`.
4. `test_status_expired_after_14_days`: monkeypatch state file `expires_at = time.time() - 1` → `status()["expired"]==True`.
5. `test_is_active_bypassed_when_license_key_set`: `monkeypatch settings.license_key="dummy"` + active demo → `is_active()==False`.

### C. License/Demo Gate Enforcement

**Yeni dosya** `app/mcp/gate.py` (~80 satır):

```python
"""MCP tool çağrılarında lisans/demo enforcement.

settings.mcp_require_license=True ise:
  - Lisans aktif → geçer
  - Demo aktif → geçer (hold count++)
  - İkisi de yok/expired → ProviderError-benzeri response: '[LİSANS GEREKLİ]'
"""
from __future__ import annotations
import logging
import time
from datetime import datetime, timezone
from functools import wraps
from typing import Any, Callable
from app.config import settings

logger = logging.getLogger(__name__)

def _gate_status() -> dict:
    """Anlık gate durumu — license_active, demo_active, allowed."""
    license_active = False
    if settings.license_key:
        try:
            from app.licensing import verify_license
            payload = verify_license(settings.license_key)
            exp = payload.get("exp", 0)
            license_active = exp > time.time()
        except Exception:
            license_active = False
    demo_active = False
    try:
        from app.licensing.demo import is_active as demo_is_active
        demo_active = demo_is_active()
    except Exception:
        demo_active = False
    allowed = (not settings.mcp_require_license) or license_active or demo_active
    return {
        "license_active": license_active,
        "demo_active": demo_active,
        "allowed": allowed,
    }

def with_gate(tool_name: str) -> Callable:
    """Decorator — MCP tool çağrısı öncesi gate check."""
    def decorator(fn: Callable) -> Callable:
        @wraps(fn)
        async def wrapper(*args: Any, **kwargs: Any) -> str:
            s = _gate_status()
            if not s["allowed"]:
                return ("[LİSANS GEREKLİ] ABS şu anda lisans gerektiriyor. "
                        "Demo süresi doldu veya lisans tanımlı değil. "
                        "Satın al: https://abs.automatiabcn.com/")
            return await fn(*args, **kwargs)
        return wrapper
    return decorator
```

**Patch** `app/mcp/middleware.py` `with_hooks` decorator'ının ALTINA — wrapper sırası: `@mcp_server.tool() → @with_gate(name) → @with_hooks(name) → async def fn`. Hooks önce çalışsın, gate ondan sonra.

**Karar:** Tüm 91 tool'a `@with_gate` eklemek mekanik refactor. **Kapsamı sınırla**: `with_hooks` decorator ZATEN gate logic'ini içerebilir. **Önerilen:** `app/mcp/middleware.py::with_hooks`'a gate çağrısı entegre et (decorator zincirini tek tut):

```python
def with_hooks(tool_name: str) -> Callable:
    def decorator(fn: Callable) -> Callable:
        @wraps(fn)
        async def wrapper(*args: Any, **kwargs: Any) -> str:
            # 011 — gate check (mcp_require_license=True ise)
            if settings.mcp_require_license:
                from app.mcp.gate import _gate_status
                s = _gate_status()
                if not s["allowed"]:
                    return ("[LİSANS GEREKLİ] ABS şu anda lisans gerektiriyor. "
                            "Demo süresi doldu veya lisans tanımlı değil.")
            # ... mevcut hook logic ...
```

Bu yaklaşımla zaten `@with_hooks` taşıyan 89 tool otomatik gated olur. **system_status** ve birkaç idle MCP tool gate dışı bırakılabilir (lisans gerekmeyen public health endpoint olarak); şimdilik tüm tool'lar gated, idle olanlar gerçekçi sonuç döner.

**Test** `tests/test_license_gate.py` (~100 satır, 4 test):

1. `test_gate_allows_when_require_license_false`: default `mcp_require_license=False` → tool normal cevap döner.
2. `test_gate_allows_when_demo_active`: `require_license=True`, demo `start_demo()` → tool çalışır.
3. `test_gate_blocks_when_demo_expired_no_license`: `require_license=True`, demo expired, no key → response `[LİSANS GEREKLİ]` ile başlar.
4. `test_gate_allows_when_license_active`: `require_license=True`, `settings.license_key=<valid jwt>` → tool çalışır.

### D. Refund Handler

**Patch** `app/api/webhooks/stripe.py` — yeni event handler:

`if event["type"] == "checkout.session.completed":` bloğunun ALTINA:

```python
if event["type"] in ("charge.refunded", "customer.subscription.deleted"):
    obj = event["data"]["object"]
    stripe_cust = obj.get("customer", "") or ""
    metadata = obj.get("metadata") or {}
    # Lisansı bul (stripe customer id veya jti meta)
    target_jti = metadata.get("license_jti")
    license_row = None
    if target_jti:
        license_row = db.scalars(select(License).where(License.jti == target_jti)).first()
    elif stripe_cust:
        license_row = db.scalars(
            select(License).where(License.customer_id_stripe == stripe_cust)
        ).first()
    if license_row is None:
        return {"status": "ok", "type": event["type"], "license_found": False}
    if license_row.revoked_at is not None:
        return {"status": "ok", "type": event["type"], "duplicate": True}
    license_row.revoked_at = datetime.now(timezone.utc)
    license_row.revoked_reason = (
        "stripe_refund" if event["type"] == "charge.refunded"
        else "stripe_subscription_deleted"
    )
    db.add(license_row)
    db.commit()
    return {"status": "ok", "type": event["type"], "revoked_jti": license_row.jti}
```

**Patch** `app/licensing/verifier.py` — `verify_license()` fonksiyonu DB'de revoked_at sorgulasın (opsiyonel, yorum açık), ya da daha basit: `app/api/license.py::status` endpoint revoked_at'i raporlasın. **Tasarım:** `verify_license` saf JWT, DB sorgulama side-effect değil. `gate._gate_status` içinde DB'den revoked_at kontrol ekle:

```python
# gate.py içinde license_active hesaplarken:
if license_active:
    from sqlmodel import Session, select
    from app.db.session import engine
    from app.db.models import License
    jti = payload.get("jti")
    if jti:
        with Session(engine) as db:
            row = db.scalars(select(License).where(License.jti == jti)).first()
            if row and row.revoked_at is not None:
                license_active = False
```

**Test** `tests/test_refund_handler.py` (~110 satır, 3 test):

1. `test_charge_refunded_revokes_license`: pre-create License (jti=X, customer_id_stripe=cus_123) → POST stripe webhook `charge.refunded` event with `customer:cus_123` → DB row.revoked_at != None.
2. `test_subscription_deleted_revokes_license`: similar with `customer.subscription.deleted`.
3. `test_refund_no_matching_license_ok_response`: webhook customer ID DB'de yok → 200 + `license_found:False`.

### E. Pricing Config + Stripe Product Setup Script

**Yeni dosya** `infra/scripts/setup_stripe_products.py` (~70 satır) — **manuel çalıştırılır, deployment doc'ı:**

```python
"""ABS Stripe Product/Price kurulum yardımcısı (TEK SEFER).

Kullanım:
  ABS_STRIPE_SECRET_KEY=sk_live_... python infra/scripts/setup_stripe_products.py

3 product oluşturur (varsa atlar):
  - ABS Self-Host ($299)
  - ABS Team Pack 5 ($1196)
  - ABS Team Pack 10 ($2093)

Output: Price ID'leri stdout. .env'e elle yapıştır:
  ABS_PRICE_SELF_HOST=price_...
  ABS_PRICE_TEAM_5=price_...
  ABS_PRICE_TEAM_10=price_...
"""
import os
import sys
import stripe

stripe.api_key = os.environ.get("ABS_STRIPE_SECRET_KEY", "")
if not stripe.api_key:
    print("ABS_STRIPE_SECRET_KEY env var gerekli", file=sys.stderr)
    sys.exit(1)

PRODUCTS = [
    {"name": "ABS Self-Host", "amount": 29900, "metadata_sku": "self-host"},
    {"name": "ABS Team Pack 5", "amount": 119600, "metadata_sku": "team-5"},
    {"name": "ABS Team Pack 10", "amount": 209300, "metadata_sku": "team-10"},
]

for spec in PRODUCTS:
    # idempotency: aynı sku metadata'lı product var mı?
    existing = stripe.Product.list(active=True, limit=100)
    found = next((p for p in existing.data
                  if (p.metadata or {}).get("sku") == spec["metadata_sku"]), None)
    if found:
        prices = stripe.Price.list(product=found.id, active=True, limit=10)
        active = next((pr for pr in prices.data if pr.unit_amount == spec["amount"]), None)
        if active:
            print(f"# {spec['metadata_sku']} mevcut: {active.id}")
            continue
    product = found or stripe.Product.create(
        name=spec["name"], metadata={"sku": spec["metadata_sku"]},
    )
    price = stripe.Price.create(
        product=product.id, currency="usd", unit_amount=spec["amount"],
    )
    env_name = f"ABS_PRICE_{spec['metadata_sku'].replace('-', '_').upper()}"
    print(f"{env_name}={price.id}")
```

**Test** `tests/test_pricing_sku_mapping.py` (~40 satır, 2 test):

1. `test_sku_self_host_seat_1`: `_SKU_TO_PRICE["self-host"][1]==1`.
2. `test_sku_team_5_and_10_seats`: `_SKU_TO_PRICE["team-5"][1]==5`, `team-10`→`10`.

### F. Panel SSE License-Status Event

**Patch** `app/api/stream.py`:

- `_EVENT_ORDER`'a `"license-status"` ekle (6. event).
- Yeni builder:

```python
def _build_license_status() -> dict:
    from app.licensing.demo import status as demo_status
    from app.mcp.gate import _gate_status
    g = _gate_status()
    d = demo_status()
    return {
        "license_active": g["license_active"],
        "demo_active": g["demo_active"],
        "demo_days_remaining": d.get("days_remaining"),
        "demo_expires_at": d.get("expires_at"),
        "require_license": settings.mcp_require_license,
        "allowed": g["allowed"],
        "purchase_url": "https://abs.automatiabcn.com/",
    }

_BUILDERS["license-status"] = _build_license_status
```

**Test** `tests/test_stream_real_data.py` patch — yeni test ekle:

```python
def test_license_status_event_payload():
    from app.api.stream import _build_license_status
    payload = _build_license_status()
    assert "license_active" in payload
    assert "demo_active" in payload
    assert "purchase_url" in payload
```

### G. MCP Tools — license_status + demo_status

**Yeni dosya** `app/mcp/tools/license_tools.py` (~50 satır, 2 tool):

```python
"""Lisans/demo durum sorgulama MCP tool'ları (011)."""
from __future__ import annotations
import json
from typing import List
from app.licensing.demo import status as demo_status_fn
from app.mcp.gate import _gate_status
from app.mcp.middleware import with_hooks
from app.mcp.server import mcp_server
from app.mcp.tracking import tracker

REGISTERED_TOOLS: List[str] = []

@mcp_server.tool()
@with_hooks("license_status")
async def license_status() -> str:
    """ABS lisans + demo durum snapshot — JSON döner."""
    await tracker.bump("license_status")
    g = _gate_status()
    d = demo_status_fn()
    return json.dumps({
        "license_active": g["license_active"],
        "demo": d,
        "require_license": False,  # placeholder — settings'ten okunsun
        "allowed": g["allowed"],
    }, ensure_ascii=False, indent=2)

@mcp_server.tool()
@with_hooks("demo_status")
async def demo_status() -> str:
    """Demo countdown durum (started/expired/days_remaining)."""
    await tracker.bump("demo_status")
    return json.dumps(demo_status_fn(), ensure_ascii=False, indent=2)

REGISTERED_TOOLS.extend(["license_status", "demo_status"])
```

**Patch** `app/mcp/server.py::register_all_tools` — `from app.mcp.tools import license_tools` import + count.

**Patch** `tests/test_tools_count.py`:
- 89 → **91 guard**
- must_have'a `"license_status"`, `"demo_status"` ekle

## Kısıtlar

- **Stripe API key** kullanıcının. Worker test'te mock kullansın, live'da kullanıcı `.env` ile sağlasın. Key task summary.md'ye **YAZILMAZ**.
- **Mevcut 11 license/stripe testi YEŞİL kalmalı** — backward compatible patch.
- **`mcp_require_license` default False** — 011 sonrası bile production'da müşteri opt-in.
- **Demo state file** `data_dir/demo_state.json` — testlerde `tmp_path` ile izole.
- **Gate decorator** `with_hooks` içine entegre — yeni decorator chain refactoru olmasın.
- **Refund webhook** mevcut `checkout.session.completed` handler ile aynı router; yeni endpoint açma.
- **pytest 155+** zorunlu.
- **Freeze AKTIF** — sadece `/Users/eneseserkan/Main/abs-server-product` içinde edit. SERVER read-only.

## Adımlar (Worker Claude için)

### 1. Önkoşul (5 dk)
```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                        # 137 passed
.venv/bin/pytest tests/test_stripe_webhook.py tests/test_license_api.py tests/test_licensing.py -v
# 11 passed
```

### 2. Modul A — Checkout Session (40 dk)
1. `app/config.py` — 3 yeni setting (`abs_price_self_host`, `abs_price_team_5`, `abs_price_team_10`)
2. `app/api/checkout.py` (yukarıdaki şablon)
3. `app/main.py` — `checkout_router` register
4. `tests/test_checkout_session.py` (4 test, monkeypatch `stripe.checkout.Session.create`)
5. `pytest tests/test_checkout_session.py -v` → 4 PASS

### 3. Modul B — Demo Mode (35 dk)
1. `app/licensing/demo.py` (yukarıdaki şablon)
2. `app/main.py::lifespan` — `start_demo()` çağrısı (license_key boşsa)
3. `app/api/license.py` — `/v1/license/demo-status` endpoint
4. `tests/test_demo_mode.py` (5 test, tmp_path data_dir)
5. `pytest tests/test_demo_mode.py -v` → 5 PASS

### 4. Modul C — License Gate (40 dk)
1. `app/mcp/gate.py` (yukarıdaki şablon, `_gate_status` + `with_gate` ikisi de export)
2. `app/mcp/middleware.py` patch — `with_hooks` decorator'ının başına gate check entegre (revoked_at DB sorgu dahil)
3. `tests/test_license_gate.py` (4 test)
4. `pytest tests/test_license_gate.py -v` → 4 PASS
5. `pytest tests/test_mcp_middleware_with_hooks.py -v` → mevcut 3 test hâlâ PASS (default require_license=False, gate no-op)

### 5. Modul D — Refund Handler (30 dk)
1. `app/api/webhooks/stripe.py` patch — `charge.refunded` + `customer.subscription.deleted` event handler ekle
2. `tests/test_refund_handler.py` (3 test, License row pre-create)
3. `pytest tests/test_refund_handler.py tests/test_stripe_webhook.py -v` → 7 PASS (3 yeni + 4 eski)

### 6. Modul E — Pricing Config + Setup Script (15 dk)
1. `infra/scripts/setup_stripe_products.py` (yukarıdaki şablon — manuel script, test edilmez sadece syntax check)
2. `tests/test_pricing_sku_mapping.py` (2 test)
3. `pytest tests/test_pricing_sku_mapping.py -v` → 2 PASS
4. `python -m py_compile infra/scripts/setup_stripe_products.py` → exit 0

### 7. Modul F — Panel SSE License-Status (15 dk)
1. `app/api/stream.py` patch — `_EVENT_ORDER` + `_build_license_status` + `_BUILDERS` mapping
2. `tests/test_stream_real_data.py` extend — yeni test
3. `pytest tests/test_stream_real_data.py -v` → 2 PASS (mevcut 1 + yeni 1)

### 8. Modul G — MCP Tools + Registry (15 dk)
1. `app/mcp/tools/license_tools.py` (2 tool)
2. `app/mcp/server.py` Read → tam Write override (license_tools import + count)
3. `tests/test_tools_count.py` patch (89 → 91, 2 yeni isim)
4. `pytest tests/test_tools_count.py -v` → 2 PASS

### 9. Tam Test Suite (5 dk)
```bash
.venv/bin/pytest -q
# 155+ passed
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 91
```

### 10. Live MCP Smoke (15 dk)
uvicorn boot + `claude mcp add abs-011` + 4 canlı kanıt:
- `license_status` → `{"license_active":false, "demo": {"started":true,...}, "allowed":true}`
- `demo_status` → `{"started":true, "active":true, "days_remaining":14}`
- POST `/v1/checkout/create-session` body=`{"sku":"self-host","customer_email":"test@example.com"}` → `[HATA]` (Stripe key yok testte) ya da gerçek `checkout_url` (key set ise)
- POST `/v1/license/demo-status` → JSON

Kanıt dosyaları `/tmp/abs-011-smoke/evidence/01-04.json`.

### 11. Tamamlama
1. `_agent-tasks/completed/011-stripe-checkout-demo-gate.md` → bu dosyayı taşı
2. `_agent-tasks/completed/011-stripe-checkout-demo-gate-summary.md` yaz:
   - 7 modül her biri ne yapıldı
   - Mevcut 11 test'in hâlâ yeşil olduğu
   - Stripe key kullanıldı mı (BELİRTME — sadece "ABS_STRIPE_SECRET_KEY env'den okundu, redacted")
   - Test sonuçları (137 → 155+)
   - Notlar Planlayıcıya

## Doğrulama (Worker fail-fast)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                                  # 155+ passed
.venv/bin/pytest tests/test_tools_count.py -v                        # 91 guard
.venv/bin/python -c "from app.mcp.server import mcp_server; import asyncio; print(len(asyncio.run(mcp_server.list_tools())))"
# 91
.venv/bin/python -c "from app.licensing.demo import start_demo, status; start_demo(); print(status())"
.venv/bin/python -m py_compile infra/scripts/setup_stripe_products.py
# exit 0
```

## Notlar Planlayıcıya (Worker doldursun)

- Stripe Product/Price ID'leri **kullanıcı manuel** oluşturacak (`setup_stripe_products.py` çalıştırıldı mı? Çıktı `.env`'de mi?). Live test sırasında kullanıcının verdiği price ID'leri sadece test için kullan.
- `mcp_require_license` default **False** kalsın — 012 (setup wizard) içinde kullanıcı kuruluştan sonra opt-in toggle eklesin.
- Demo state file `data_dir/demo_state.json` Docker volume'unda persist olur. Production'da müşteri Docker volume sildiğinde demo reset — istemiyorsa bu önemli; gerçi 14 gün sonrası "abused" sayılır. Şu an policy: tek kurulum tek demo, volume reset → fresh demo (kabul).
- Refund handler `charge.refunded` `customer` field tek source-of-truth; `metadata.license_jti` opsiyonel. Müşteri çoklu lisansa sahipse webhook hangi lisansı revoke edecek? **Karar:** ilk eşleşen aktif lisans (revoked_at NULL). Çoklu lisans edge case 012+'a.
- Email template `templates/license_delivery.html` zaten var — refund email template eksik. 012'de eklenebilir (refund onay mailı).
- 012 (setup wizard) **bu task'a bağımlı** — checkout endpoint + demo countdown UI'ya feed verecek.

## Kapsam Dışı (012+'a)

- Setup wizard (web UI 6 adım) — 012'nin tamamı
- Encrypted secrets (age/sops) — 012
- Email template refund/expiration — 012
- Stripe Customer Portal entegrasyonu — 013+
- Multi-license per customer — edge case, 013+
- Audit log (kim ne zaman lisans aktive etti) — 013+
