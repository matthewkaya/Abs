# Task 011 — Checkout Session + Demo Mode + License Gate + Refund + Pricing (SUMMARY)

**Tamamlandı:** 2026-04-25
**Süre:** ~1 saat (planlanan 3-4h altında — şablonlar tam)
**Sonuç:** 7 modül + Registry + py_compile script smoke. Hepsi yeşil.

## Özet

| Hedef | Önce | Sonra | Δ |
|-------|------|-------|---|
| pytest yeşil | 137 | **158** | +21 |
| MCP tool sayısı | 89 | **91** | +2 (`license_status`, `demo_status`) |
| Mevcut 11 license/stripe testi | 11 yeşil | **11 yeşil** | korundu |
| Checkout endpoint | yok | `POST /v1/checkout/create-session` | yeni |
| Demo countdown | yok | 14 gün, idempotent | yeni |
| License gate | yok | `with_hooks` içine entegre | yeni |
| Refund flow | yok | `charge.refunded` + `subscription.deleted` | yeni |
| pyproject.toml setup | manuel | `infra/scripts/setup_stripe_products.py` | yeni |
| SSE event sayısı | 5 | **6** (+`license-status`) | yeni |

## Stripe API Key Notu

Stripe secret + webhook secret **`ABS_STRIPE_SECRET_KEY` / `ABS_STRIPE_WEBHOOK_SECRET` env'den okundu — [REDACTED]**. Yeni key oluşturulmadı; testlerde tüm Stripe API çağrıları `monkeypatch` ile mock'landı (`stripe.checkout.Session.create`, `stripe.Webhook.construct_event`). Live Stripe API hiçbir testte çağrılmadı. Price ID'leri kullanıcı `infra/scripts/setup_stripe_products.py` ile manuel oluşturup `.env`'e yazacak.

## Modul A — Checkout Session Endpoint

**Yeni dosya:** `app/api/checkout.py` (~85 satır)
- `POST /v1/checkout/create-session` — `sku ∈ {self-host, team-5, team-10}` + `customer_email` (Pydantic `EmailStr`)
- `_SKU_TO_PRICE` dict (resolver lambda + seat_count) — 011 mapping tek source-of-truth
- 503: `stripe_secret_key` boş veya price_id eksik
- 422: invalid sku (Pydantic `Literal`)
- 502: `stripe.error.StripeError` graceful handling
- 200: `checkout_url` + `session_id`

**Yeni test:** `tests/test_checkout_session.py` (4 test, 89 satır) → **4/4 PASS**

**Patch'ler:**
- `app/config.py` — `abs_price_self_host`, `abs_price_team_5`, `abs_price_team_10` (3 yeni env)
- `app/main.py` — `checkout_router` register

## Modul B — Demo Mode + 14-Day Countdown

**Yeni dosya:** `app/licensing/demo.py` (~90 satır)
- `start_demo()` — idempotent, `data_dir/demo_state.json` atomic write
- `status()` — UI feed (`started`, `active`, `expired`, `days_remaining`, `expires_at`)
- `is_active()` — `settings.license_key` set → False (lisans demo bypass eder)
- `reset()` — test/dev için state sil
- `DEMO_DURATION_DAYS = 14`

**Patch'ler:**
- `app/main.py::lifespan` — `license_key` boşsa `start_demo()` (idempotent)
- `app/api/license.py` — yeni `GET /v1/license/demo-status` endpoint

**Yeni test:** `tests/test_demo_mode.py` (6 test, ~95 satır) → **6/6 PASS** (5 zorunlu + 1 endpoint regression)

## Modul C — License/Demo Gate

**Yeni dosya:** `app/mcp/gate.py` (~95 satır)
- `_gate_status()` — `license_active` (JWT verify + DB revoke check) + `demo_active` + `allowed` (require_license=False ise her zaman True)
- `_license_revoked_in_db(jti)` — refund flow için ek DB sorgu (`License.revoked_at IS NOT NULL`)
- `with_gate(tool_name)` — opsiyonel tek-tool wrapper (with_hooks zaten içinde çağırıyor; refactor önlendi)
- `_BLOCK_MESSAGE` — `[LISANS GEREKLI] ...` → kullanıcı satın alma URL'i

**Patch:** `app/mcp/middleware.py::with_hooks` — decorator wrapper başına gate check (`mcp_require_license=True` ise allowed=False'da `_BLOCK_MESSAGE` döner, hook chain çalışmaz). `mcp_require_license` default **False** olduğu için 89 mevcut tool davranışı değişmedi.

**Yeni test:** `tests/test_license_gate.py` (4 test, ~95 satır) → **4/4 PASS**
- `require_license=False` → tool normal cevap
- `require_license=True` + demo aktif → tool çalışır
- `require_license=True` + demo expired + key yok → `[LISANS GEREKLI]` (Türkçe normalize: ASCII döner; testte `startswith` her iki form'u kabul ediyor)
- `require_license=True` + valid JWT → tool çalışır

**Regression:** `tests/test_mcp_middleware_with_hooks.py` mevcut 3 test hâlâ yeşil (default require_license=False, gate no-op).

## Modul D — Refund Handler

**Patch:** `app/api/webhooks/stripe.py` — `checkout.session.completed` ile aynı router'a iki yeni event:
- `charge.refunded` → `revoked_reason="stripe_refund"`
- `customer.subscription.deleted` → `revoked_reason="stripe_subscription_deleted"`

License lookup öncelik:
1. `metadata.license_jti` varsa (multi-license edge case için yer hazır, 013+'a ertelendi)
2. `customer` Stripe ID + `revoked_at IS NULL` (ilk eşleşen aktif lisans)

Idempotent: zaten `revoked_at != None` ise `duplicate: True` döner.
Lisans bulunamazsa: `license_found: False` (200, retry önlemek için).

**`verify_license` saf JWT kaldı** (DB sorgusu yok); revoked_at kontrolü `gate._gate_status()` içinde — `app/api/license.py::status` endpoint'inde de yapılabilir (012'de eklenebilir; 011 kapsam dışı).

**Yeni test:** `tests/test_refund_handler.py` (3 test, ~110 satır) → **3/3 PASS**
**Regression:** `tests/test_stripe_webhook.py` 4/4 hâlâ yeşil (toplam **7/7** stripe webhook).

## Modul E — Pricing Config + Setup Script

**Yeni dosya:** `infra/scripts/setup_stripe_products.py` (~75 satır)
- 3 product (`ABS Self-Host` $299 / `ABS Team Pack 5` $1196 / `ABS Team Pack 10` $2093)
- Idempotency: `metadata.sku` ile mevcut product ara, eşleşen `unit_amount` price varsa atla
- Output: `ABS_PRICE_*=price_...` satırları stdout'a — kullanıcı `.env`'e elle yapıştırır

**Yeni test:** `tests/test_pricing_sku_mapping.py` (3 test, ~40 satır) → **3/3 PASS**
- `_SKU_TO_PRICE["self-host"][1] == 1`
- `team-5` → 5 seat, `team-10` → 10 seat
- `py_compile` script syntax check

**py_compile doğrulama:**
```bash
.venv/bin/python -m py_compile infra/scripts/setup_stripe_products.py  # exit 0 ✓
```

## Modul F — Panel SSE License-Status Event

**Patch:** `app/api/stream.py`
- `_EVENT_ORDER` → `"license-status"` 6. event olarak eklendi
- `_build_license_status()` — gate + demo birleşik feed
- `_BUILDERS["license-status"] = _build_license_status`

**Yeni test:** `tests/test_stream_real_data.py` extend → **2/2 PASS** (mevcut 1 + yeni 1)
- Payload kontratı: `license_active`, `demo_active`, `demo_days_remaining`, `require_license`, `allowed`, `purchase_url`

## Modul G — MCP Tools + Registry

**Yeni dosya:** `app/mcp/tools/license_tools.py` (~50 satır, 2 tool)
- `license_status` — gate + demo + require_license + purchase_url snapshot
- `demo_status` — demo countdown JSON

**Patch:** `app/mcp/server.py` (tam Write override) — `license_tools` import + count.
**Patch:** `tests/test_tools_count.py` — 89 → **91 guard**, must_have'a 2 yeni tool.

**Test:** `tests/test_tools_count.py` 2/2 PASS. `_REGISTERED_COUNT == 91`.

## Test Sonuçları

```
.venv/bin/pytest -q
158 passed in 3.72s
```

**Önce:** 137. **Sonra:** 158. **Hedef:** 155+. **+21 yeni test** (4 checkout + 6 demo + 4 gate + 3 refund + 3 pricing + 1 stream license-status; spec 18 öngörmüştü, 21 yazıldı çünkü demo ekstra endpoint regression + pricing ekstra py_compile testi eklendi).

**Mevcut 11 license/stripe testi:**
```
tests/test_stripe_webhook.py    4/4 PASS  (refund handler eklendikten sonra hâlâ)
tests/test_license_api.py       3/3 PASS
tests/test_licensing.py         4/4 PASS
                              ────────
                                11/11 PASS  ✓
```

**Diğer regresyon:**
```
tests/test_mcp_middleware_with_hooks.py   3/3 PASS  (gate no-op default)
tests/test_panel_widgets.py / test_panel  hâlâ yeşil
```

## Live MCP Smoke (4 Kanıt)

uvicorn `--port 8766` (env override: tmp dirs). Kanıtlar `/tmp/abs-011-smoke/evidence/`:

### 1. `license_status` (MCP) → require_license=False, demo aktif, allowed=true
```json
{
  "license_active": false,
  "demo": {
    "started": true, "active": true, "expired": false,
    "days_remaining": 13, "started_at": 1777118697.93, "expires_at": 1778328297.93
  },
  "require_license": false,
  "allowed": true,
  "purchase_url": "https://abs.automatiabcn.com/"
}
```

### 2. `demo_status` (MCP) → 13 gün kalan
```json
{"started": true, "active": true, "expired": false, "days_remaining": 13, ...}
```

### 3. `POST /v1/checkout/create-session` (REST, sku=self-host) → 503 (stripe_key boş — beklenen)
```
HTTP/1.1 503 Service Unavailable
{"detail":"Stripe yapılandırılmadı"}
```
Doğru graceful: stripe key yokken 503, body'de Türkçe hata. Live Stripe çağrısı yapılmadı.

### 4. `GET /v1/license/demo-status` (REST) → JSON
```json
{"started":true,"active":true,"expired":false,"days_remaining":13,"started_at":1777118697.93,"expires_at":1778328297.93}
```

MCP tools/list = **91**, init handshake OK, `notifications/initialized` ok.

## Notlar Planlayıcıya

1. **Stripe Product/Price kurulumu kullanıcı işi.** `infra/scripts/setup_stripe_products.py` tek-sefer manuel çalıştırılır; çıkan `ABS_PRICE_*=price_...` satırları `.env.local`'a yapıştırılmalı. Kullanıcı bunu henüz çalıştırmadı (key Stripe Dashboard'dan veya CLI ile alınacak); 011'de live Stripe API'ye dokunulmadı.

2. **`mcp_require_license` default False.** 012 (setup wizard) içinde toggle eklenecek. Production müşteri kuruluştan sonra opt-in yapacak; 011 sonrası bile var-sayım: lisans gerekmiyor.

3. **Demo state file `data_dir/demo_state.json`.** Docker volume sıfırlanırsa yeniden 14 gün başlar. Politika: tek kurulum tek demo, volume reset = abuse → 14 gün karşılığında "tek seferlik" anlam taşır. Production'da 012 setup wizard demo'yu kullanıcı email'e bağlayabilir (anti-abuse).

4. **Refund "ilk eşleşen aktif lisans" kuralı.** `metadata.license_jti` öncelikli; yoksa `customer_id_stripe` + `revoked_at IS NULL` ilk eşleşen. **Çoklu lisans edge case 013+'a.** Çözüm önerisi: webhook frontend (Stripe Dashboard) `metadata.license_jti` zorunlu kılınsın → eski lisanslarda yok, yeni lisanslarda checkout flow'unda `metadata` injekte edilsin (014).

5. **`verify_license` saf JWT** — DB sorgu yok. Refund flow'da revoke check `gate._gate_status()` içinde (her MCP tool çağrısı). `GET /v1/license/status` endpoint'i 011 itibarıyla revoked_at'i raporlamıyor — bu davranış 012'de UI banner'a feed olunca eklenmeli.

6. **Email refund template eksik.** `templates/license_delivery.html` zaten var; `license_revoked.html` yok. 012'de eklenmeli — refund webhook'u şu an mail göndermiyor (gerçi Stripe kendi refund onay maili atar; çift mail gereksiz olabilir).

7. **SSE `license-status` event** panel `_EVENT_ORDER`'a 6. eklendi. Frontend HTML'de banner widget henüz tanımlı değil — 012 setup wizard içinde panel UI bu event'i dinleyecek.

8. **License gate decorator `with_hooks`'a entegre.** Spec'in önerdiği gibi yeni decorator chain açılmadı; mevcut 89 tool otomatik gated oldu.

9. **`mcp_require_license=True` testte mock'lu** — gerçek 89 tool gate altında olduğunda gerçek davranış sınanmadı. 012'de panel toggle ile birlikte E2E senaryo eklenmeli.

10. **Stripe webhook `revoked_at.is_(None)` filter** SQLModel/SQLAlchemy `IS NULL` syntax — pyright `revoked_at` Optional[datetime] üzerinde `.is_()` görmüyor (type ignore eklendi). Runtime sorunsuz; 012'de cleaner SQL syntax değerlendirilebilir.

## Feature Parity

011 SERVER paritesinden **ileriye geçer**:
- Demo countdown: SERVER'da yok (her müşteri demo başlatma kavramı self-host ABS'ye özgü).
- License gate `with_hooks` integration: SERVER yapısı farklı (orchestrator pattern); ABS-specific hardening.
- Refund flow: Stripe webhook'a 2 ek event handler — SERVER'da yok.
- Pricing config + setup script: ABS deployment artifact'ı.

Atlanan parity yok.

## Doğrulama (Fail-Fast)

```bash
$ .venv/bin/pytest -q
158 passed in 3.72s

$ .venv/bin/pytest tests/test_tools_count.py -v
2 passed

$ .venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
91

$ .venv/bin/python -c "from app.mcp.server import mcp_server; import asyncio; print(len(asyncio.run(mcp_server.list_tools())))"
91

$ .venv/bin/python -c "from app.licensing.demo import start_demo, status; start_demo(); print(status())"
{'started': True, 'active': True, 'expired': False, 'days_remaining': 13, ...}

$ .venv/bin/python -m py_compile infra/scripts/setup_stripe_products.py
# exit 0
```

Hepsi yeşil.

## Kapsam Dışı (012+'a)

- Setup wizard web UI (6 adım) — **012'nin tamamı**
- Encrypted secrets (age/sops) — 012
- Email template refund/expiration — 012
- Stripe Customer Portal entegrasyonu — 013+
- Multi-license per customer (refund target seçimi) — 013+
- Audit log (lisans aktive/revoke trail) — 013+
- License `GET /v1/license/status` revoked_at raporu — 012
- Panel HTML banner widget (license-status SSE consumer) — 012
