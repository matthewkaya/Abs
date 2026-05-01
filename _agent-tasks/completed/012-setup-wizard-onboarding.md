# Task 012 — Setup Wizard + First-Run Redirect + Demo Banner + Email Templates

**Tahmini süre:** 4-5 saat (6 modül + UI + middleware + 3 email template)
**Önkoşul:** 011 tamam (91 MCP tool, 158/158 pytest yeşil, demo mode + license_status SSE event yazıldı)

## Bağlam

011 sonunda **demo mode 14-gün countdown** + **`license-status` SSE event** + **`license_status`/`demo_status` MCP tools** + **`/v1/license/demo-status` REST** hazır. Eksik olan **müşteri tarafında ilk kurulum UX'i**:

- Müşteri Docker compose ayağa kaldırdı → tarayıcıda `https://sunucu/setup` açılır → 6 adım wizard tamamlanmadan ABS hiçbir endpoint'e cevap vermez (sadece `/setup/*`, `/healthz`, static assets erişilebilir)
- Setup tamamlanınca `/panel`'e redirect, demo countdown banner görünür
- Refund/expiration email template'leri webhook ve cron tarafında çağrılabilir

**design-decisions.md md.4 + md.14 + md.15 + md.21** bu task'ın referansı. **architecture.md §6 müşteri çalışma akışı** birebir uygulanır.

012 **6 modül** ekler — sıfırdan inşa, mevcut auth/email/panel altyapısı üzerine:

1. **Setup state + endpoints** (`/v1/setup/*`) — 6 adım state machine (data_dir/setup_state.json), advance/back/status
2. **First-run middleware** — setup tamamlanmadıysa `/setup`'a redirect; whitelist (`/healthz`, `/v1/setup/*`, `/setup`, `/panel/assets/*`, `/static/*`)
3. **Setup UI** — `app/static/setup/index.html` + `assets/setup.js` brand-uyumlu vanilla 6 adım wizard (mevcut panel CSS token'ları yeniden kullan)
4. **Panel demo countdown banner** — `app/static/panel/index.html` + `assets/panel.js` patch (mevcut SSE `license-status` event'ini banner element'ine bağla)
5. **Email templates** — `license_refund.html` + `license_expired.html` + sender fonksiyonları (`send_refund_email`, `send_expiration_email`)
6. **MCP tool: setup_status** — Claude Code'dan müşteri kurulumu durumu sorgulansın

**Tool sayısı hedefi:** 91 → **92 tool** (+1: `setup_status`).
**Test sayısı hedefi:** 158 → **~178+ test** (+20: 7 setup wizard, 4 first-run middleware, 3 panel banner, 3 email templates, 2 setup UI, 1 mcp tool).

## Giriş (Mevcut Durum — Worker doğrulasın)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                                       # 158 passed
.venv/bin/python -c "from app.api.license import router; print([r.path for r in router.routes])"
# /v1/license/activate, /v1/license/status, /v1/license/demo-status (011)
ls app/email/templates/                                                   # license_delivery.html (mevcut)
ls app/static/panel/                                                      # index.html, login.html, assets/ (mevcut)
```

**Mevcut altyapı:**
- `app/api/auth.py` — bcrypt + JWT cookie, ADMIN_EMAIL hardcoded `admin@local`, password env var (`ADMIN_PASSWORD_BOOTSTRAP`)
- `app/email/sender.py` — `_render(template, **ctx)`, `send_license_email`, SMTP veya console fallback
- `app/static/panel/{index.html,login.html,assets/}` — mevcut panel
- `app/api/license.py` — `/v1/license/{activate,status,demo-status}` endpoint'leri
- `app/licensing/demo.py` — `start_demo`, `status`, `is_active`
- `app/config.py` — `admin_email`, `admin_password_bootstrap`, `domain`, `ssl_mode`, `data_dir`

**Yeni dosyalar (012):**
- `app/api/setup.py` — 6 adım wizard endpoint'leri
- `app/middleware/first_run.py` — first-run redirect middleware
- `app/static/setup/index.html` + `assets/setup.css` + `assets/setup.js`
- `app/email/templates/license_refund.html`
- `app/email/templates/license_expired.html`
- `app/mcp/tools/setup_tools.py`
- 6 test dosyası

**Patch'lenecek dosyalar:**
- `app/main.py` — setup_router register + first_run middleware mount + static `/setup/assets` mount
- `app/api/license.py` — refund/expiration email integration (refund webhook'ta çağır)
- `app/api/webhooks/stripe.py` — refund handler `send_refund_email` çağır
- `app/email/sender.py` — `send_refund_email`, `send_expiration_email` fn'ları
- `app/static/panel/index.html` + `assets/panel.js` — demo countdown banner UI
- `app/mcp/server.py` — setup_tools register
- `tests/test_tools_count.py` — 91 → 92 + `setup_status` must_have

## Beklenen Çıktı

### A. Setup State + Endpoints

**Yeni dosya** `app/api/setup.py` (~220 satır):

State machine — 6 adım:

| # | Adım | Body | Validation |
|---|------|------|------------|
| 1 | `admin` | `{email, password}` | email format, password >= 8 char |
| 2 | `license` | `{license_key}` | `verify_license(key)` → JWT valid + not expired + not revoked (DB) |
| 3 | `domain` | `{mode: "ip"\|"domain", domain?, ssl_mode: "internal"\|"acme"}` | mode=domain ise domain regex |
| 4 | `anthropic` | `{anthropic_api_key}` | format `sk-ant-...` (basic regex) |
| 5 | `providers` | `{groq_api_key?, gemini_api_key?, cerebras_api_key?, cohere_api_key?, cf_account_id?, cf_api_token?}` | hepsi opsiyonel; en az 0 OK |
| 6 | `test` | `{}` (server-side test çalıştırır) | her configured provider'a 1 test çağrı (mock'lanabilir) |

**State file** `<data_dir>/setup_state.json`:
```json
{
  "completed": false,
  "current_step": 1,
  "completed_steps": [],
  "started_at": 1780000000,
  "completed_at": null,
  "data": {
    "admin": {"email": "admin@example.com"},
    "license": {"jti": "...", "tier": "self-host", "seat_count": 1},
    "domain": {"mode": "ip", "ssl_mode": "internal"},
    "anthropic_configured": false,
    "providers_configured": [],
    "test_results": {}
  }
}
```

API:
- `GET /v1/setup/status` → state JSON
- `POST /v1/setup/step/admin` → adım 1 ilerlet
- `POST /v1/setup/step/license` → adım 2
- `POST /v1/setup/step/domain` → adım 3
- `POST /v1/setup/step/anthropic` → adım 4
- `POST /v1/setup/step/providers` → adım 5
- `POST /v1/setup/step/test` → adım 6 (provider ping) → setup completed
- `POST /v1/setup/reset` → dev-only, `settings.env=="dev"` ise state sil

**Persistence:** her başarılı step'ten sonra:
- Admin password → `bcrypt.hashpw` → `data_dir/admin_credentials.json` (ileride DB; şimdilik dosya)
- License key → `settings.license_key` runtime + `.env` patch (mevcut `_persist_license_key_to_env`)
- API keys → `.env` patch (`ABS_ANTHROPIC_API_KEY=...` vb.)
- Domain → `.env` patch (`ABS_DOMAIN=...`, `ABS_SSL_MODE=...`)
- Test results → setup_state.json `data.test_results`

**Setup tamamlanınca** `setup_state.completed=True` + `completed_at=now`. First-run middleware bu flag'i okur.

**Test** `tests/test_setup_wizard.py` (~220 satır, 7 test):

1. `test_get_status_initial`: setup state yok → `{completed:false, current_step:1, completed_steps:[]}`.
2. `test_admin_step_creates_credentials_file`: POST `/v1/setup/step/admin` `{email,password}` → `data_dir/admin_credentials.json` var, password bcrypt hash, `setup_state.current_step==2`.
3. `test_license_step_validates_jwt`: invalid token → 400. Valid token (test fixture: `generate_license` ile üretilmiş JWT) → `current_step==3`, `data.license.jti` set.
4. `test_domain_step_persists_to_env`: `{mode:"ip"}` → `current_step==4`, `.env` (tmp) patched.
5. `test_anthropic_step_validates_format`: `{anthropic_api_key:"invalid"}` → 400. `sk-ant-test123` → 200, `current_step==5`.
6. `test_providers_step_optional`: empty body `{}` → 200, `current_step==6`. With keys → all stored in `.env`.
7. `test_complete_step_sets_completed_flag`: setup state at step 6 → POST `/v1/setup/step/test` → `setup_state.completed==True`, `current_step` constant 6, `completed_at != None`.

### B. First-Run Redirect Middleware

**Yeni dosya** `app/middleware/__init__.py` + `app/middleware/first_run.py` (~80 satır):

```python
"""First-run redirect — setup tamamlanmadıysa /setup'a yönlen.

Whitelist: /healthz, /v1/setup/*, /setup, /setup/*, /panel/assets/*, /static/*
Whitelist dışı her istek → 302 redirect /setup
Setup tamamlandıktan sonra middleware no-op.
"""
from __future__ import annotations
import re
from pathlib import Path
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import RedirectResponse
from app.config import settings

_WHITELIST_PREFIXES = (
    "/healthz", "/v1/setup", "/setup", "/panel/assets/",
    "/setup/assets/", "/static/", "/_internal/",
)

class FirstRunMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        # Setup tamamlanmış mı? — her istekte cache miss yapma, dosya sadece değişince oku
        if self._setup_completed():
            return await call_next(request)
        path = request.url.path
        if any(path.startswith(p) for p in _WHITELIST_PREFIXES):
            return await call_next(request)
        # Hot path: API isteklerine 503 (browser olmayabilir), browser'a 302
        accept = request.headers.get("accept", "")
        if "text/html" in accept:
            return RedirectResponse(url="/setup", status_code=302)
        return RedirectResponse(url="/setup", status_code=307)

    def _setup_completed(self) -> bool:
        from app.api.setup import setup_state_path  # lazy import
        p = setup_state_path()
        if not p.is_file():
            return False
        try:
            import json
            return bool(json.loads(p.read_text()).get("completed"))
        except Exception:
            return False
```

**Patch** `app/main.py`:
```python
from app.middleware.first_run import FirstRunMiddleware
# ...
app.add_middleware(FirstRunMiddleware)
```

**Test** `tests/test_first_run_middleware.py` (~110 satır, 4 test):

1. `test_redirects_when_setup_incomplete`: setup state yok → GET `/panel` → 302 → location `/setup`.
2. `test_no_redirect_for_whitelist`: GET `/healthz` → 200. GET `/v1/setup/status` → 200.
3. `test_no_redirect_when_completed`: setup_state.json `completed:true` → GET `/panel` → 200 (veya 401, redirect değil).
4. `test_api_request_gets_307_not_html`: `Accept: application/json` + setup incomplete → 307 (idempotent for non-GET).

### C. Setup UI (Static HTML/JS)

**Yeni dosya** `app/static/setup/index.html` (~180 satır):

- Brand-uyumlu (mevcut panel CSS token'ları reuse — `--brand-primary #1e57ac`, `--brand-gradient`)
- 6 step indicator (üst breadcrumb)
- Tek sayfa — JS ile step görünürlüğü değiştir
- Her step inline form + "Geri" / "İleri" buton
- Progress bar
- Logo SVG (mevcut panel'den kopya: `.logo-mark` izometrik mavi küp)
- Tagline "Automate the Chaos"

Step elementleri:

```html
<section class="setup-step" data-step="1">
  <h2>1. Yönetici Hesabı</h2>
  <input name="email" type="email" required>
  <input name="password" type="password" minlength="8" required>
  <button class="setup-next" data-step-key="admin">İleri</button>
</section>

<section class="setup-step" data-step="2" hidden>
  <h2>2. Lisans Anahtarı</h2>
  <textarea name="license_key" rows="4" required></textarea>
  <p class="setup-help">Email ile aldığınız JWT lisansı yapıştırın. <a href="/setup#demo">Demo modunda devam et</a></p>
  <button class="setup-back">Geri</button>
  <button class="setup-next" data-step-key="license">İleri</button>
</section>

<!-- ... 3-6 ... -->

<section class="setup-step" data-step="6" hidden>
  <h2>6. Provider Testi</h2>
  <div id="setup-test-results"></div>
  <button class="setup-back">Geri</button>
  <button class="setup-finish" data-step-key="test">Kuruluma Başla</button>
</section>
```

**JS** `app/static/setup/assets/setup.js` (~180 satır):
- `fetch('/v1/setup/status')` boot'ta state oku → current_step UI'da görünür yap
- Her "İleri" butonu → ilgili POST `/v1/setup/step/{key}`, başarılıysa next step göster
- Adım 6 finish → POST → success → `window.location='/panel/login'` 1.5s sonra
- Hata → inline alert (`<div class="setup-error">...</div>`)

**Static mount** `app/main.py`:
```python
SETUP_STATIC_DIR = Path(__file__).resolve().parent / "static" / "setup"
app.mount("/setup/assets", StaticFiles(directory=str(SETUP_STATIC_DIR / "assets")), name="setup-assets")

@app.get("/setup", include_in_schema=False)
async def setup_index():
    return FileResponse(SETUP_STATIC_DIR / "index.html")
```

**Test** `tests/test_setup_ui.py` (~50 satır, 2 test):

1. `test_setup_index_serves_html`: GET `/setup` → 200, `text/html`, body içerir `data-step="1"`.
2. `test_setup_assets_served`: GET `/setup/assets/setup.js` → 200, `application/javascript`.

### D. Panel Demo Countdown Banner

**Patch** `app/static/panel/index.html`:

```html
<!-- Header altında, panel-grid üstünde -->
<div id="demo-banner" class="demo-banner" hidden>
  <span class="demo-banner-icon">⏳</span>
  <span class="demo-banner-text">
    Demo modu: <strong id="demo-days">14</strong> gün kaldı.
    <a href="https://abs.automatiabcn.com/" target="_blank">Lisans satın al</a>
  </span>
  <button class="demo-banner-dismiss" onclick="dismissDemoBanner()">×</button>
</div>
```

**Patch** `app/static/panel/assets/panel.css`:

```css
.demo-banner {
  background: linear-gradient(90deg, var(--brand-primary), var(--brand-primary-bright));
  color: white;
  padding: 12px 20px;
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 14px;
}
.demo-banner.demo-warn  { background: #f59e0b; }
.demo-banner.demo-danger { background: #ef4444; }
.demo-banner-text a { color: white; text-decoration: underline; font-weight: 600; }
.demo-banner-dismiss { margin-left: auto; background: none; border: 0; color: white; font-size: 20px; cursor: pointer; }
```

**Patch** `app/static/panel/assets/panel.js`:

```javascript
// SSE 'license-status' event handler (mevcut sse setup'a ekle)
sse.addEventListener('license-status', (ev) => {
  const d = JSON.parse(ev.data);
  const banner = document.getElementById('demo-banner');
  if (!banner) return;
  if (d.license_active) { banner.hidden = true; return; }
  if (!d.demo_active) {
    banner.hidden = false;
    banner.classList.add('demo-danger');
    document.getElementById('demo-days').textContent = '0';
    return;
  }
  banner.hidden = false;
  const days = d.demo_days_remaining ?? 14;
  document.getElementById('demo-days').textContent = days;
  banner.classList.toggle('demo-warn', days <= 7 && days > 3);
  banner.classList.toggle('demo-danger', days <= 3);
});

function dismissDemoBanner() {
  document.getElementById('demo-banner').hidden = true;
  // 24h TTL ile localStorage flag (gün başına 1 dismiss)
  localStorage.setItem('abs_demo_banner_dismissed_at', Date.now());
}
```

**Test** `tests/test_panel_banner.py` (~70 satır, 3 test):

1. `test_panel_html_contains_demo_banner`: GET `/panel/login` → 200; `/panel` (auth gerektirir, mock cookie) → response body `id="demo-banner"`.
2. `test_panel_js_handles_license_status_event`: `panel.js` static dosyası `addEventListener('license-status'` içerir.
3. `test_panel_css_demo_banner_classes`: `panel.css` `.demo-banner`, `.demo-warn`, `.demo-danger` class tanımları içerir.

### E. Email Templates — Refund + Expiration

**Yeni dosya** `app/email/templates/license_refund.html` (~50 satır):

```html
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <title>İade onayı — Automatia ABS</title>
  <!-- subject: Automatia ABS satın alımınız iade edildi -->
</head>
<body style="font-family: Arial, sans-serif; ...">
  <div style="max-width: 600px; margin: 20px auto; ...">
    <h2>İade onayınız</h2>
    <p>Merhaba {{ customer_email }},</p>
    <p>{{ refund_date }} tarihinde işlenen iade talebiniz tamamlandı.</p>
    <p>Lisansınız ({{ license_jti }}) iptal edildi. ABS sunucunuz şu andan itibaren demo moda dönmüştür.</p>
    <p>Geri bildiriminizi paylaşırsanız çok mutlu oluruz: <a href="mailto:hi@automatiabcn.com">hi@automatiabcn.com</a></p>
    <p>İyi çalışmalar,<br>Automatia BCN</p>
  </div>
</body>
</html>
```

**Yeni dosya** `app/email/templates/license_expired.html` (~50 satır) — benzer format, "Lisansınızın süresi {{ expired_at }} tarihinde doldu, yenilemek için: ..." içerir.

**Patch** `app/email/sender.py`:

```python
def send_refund_email(*, to: str, license_jti: str, refund_date: str) -> None:
    subject, html = _render(
        "license_refund.html",
        customer_email=to, license_jti=license_jti, refund_date=refund_date,
    )
    if not settings.smtp_host:
        logger.info("[email:console-fallback] refund to=%s subject=%r", to, subject)
        return
    # ... SMTP gönderim (mevcut send_license_email pattern'i tekrar)

def send_expiration_email(*, to: str, license_jti: str, expired_at: str) -> None:
    # benzer
```

**Patch** `app/api/webhooks/stripe.py` — refund handler'da:
```python
# 011'de eklenmiş revoke logic'inden sonra:
try:
    from app.email.sender import send_refund_email
    send_refund_email(
        to=license_row.customer_email,
        license_jti=license_row.jti,
        refund_date=license_row.revoked_at.strftime("%Y-%m-%d"),
    )
except Exception as exc:
    logger.exception("refund email gönderim: %s", exc)
```

**Test** `tests/test_email_templates.py` (~80 satır, 3 test):

1. `test_refund_email_renders`: `_render("license_refund.html", customer_email="x@y.com", license_jti="abc", refund_date="2026-04-25")` → HTML içerir `x@y.com` + `abc` + `2026-04-25`.
2. `test_expiration_email_renders`: benzer.
3. `test_refund_email_console_fallback`: `monkeypatch settings.smtp_host=""` → `send_refund_email` exception fırlatmaz, log mesajı atılır.

### F. MCP Tool — setup_status

**Yeni dosya** `app/mcp/tools/setup_tools.py` (~40 satır):

```python
"""Setup wizard durum sorgulama MCP tool (012)."""
from __future__ import annotations
import json
from typing import List
from app.mcp.middleware import with_hooks
from app.mcp.server import mcp_server
from app.mcp.tracking import tracker

REGISTERED_TOOLS: List[str] = []

@mcp_server.tool()
@with_hooks("setup_status")
async def setup_status() -> str:
    """Müşteri kurulum wizard'ının mevcut durumu — JSON döner."""
    await tracker.bump("setup_status")
    from app.api.setup import read_state
    return json.dumps(read_state(), ensure_ascii=False, indent=2)

REGISTERED_TOOLS.extend(["setup_status"])
```

**Patch** `app/mcp/server.py::register_all_tools` — `from app.mcp.tools import setup_tools` import + count.

**Patch** `tests/test_tools_count.py`:
- 91 → **92 guard**
- must_have'a `"setup_status"` ekle

## Kısıtlar

- **Mevcut 14 license/stripe/middleware testi YEŞİL kalmalı** (test_stripe_webhook 4 + test_license_api 3 + test_licensing 4 + test_mcp_middleware 3).
- **First-run middleware setup completed sonrası NO-OP** — testlerde mevcut endpoint testleri (panel, hooks, vs.) bozulmasın. Çözüm: test conftest'inde `setup_state.json` `completed:true` fixture (autouse).
- **Auth bcrypt zaten mevcut** — yeni hash fonksiyonu yazma. Adım 1'de `_hash_password` reuse.
- **Setup state file** `data_dir/setup_state.json` — testlerde `tmp_path data_dir` ile izole.
- **Setup UI vanilla HTML/JS** — framework yok (panel pattern'i tutarlı). Inline CSS minimal, gerisi `setup.css`.
- **`.env` patch güvenliği**: `_persist_license_key_to_env` mevcut pattern (atomic temp+rename). Yeni env var'lar için generic `_persist_env_var(key, value)` fn ekle.
- **Email console fallback** — SMTP yokken testler `caplog` ile log mesajını kontrol etsin.
- **Demo banner**: lisans aktive edilince hide; demo expired'da `demo-danger` class.
- **pytest 178+** zorunlu.
- **Freeze AKTIF** — sadece `/Users/eneseserkan/Main/abs-server-product` içinde edit.

## Adımlar (Worker Claude için)

### 1. Önkoşul (5 dk)
```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                                       # 158 passed
ls app/email/templates/                                                   # license_delivery.html
ls app/static/panel/                                                      # index.html, login.html, assets/
```

### 2. Modul A — Setup State + Endpoints (60 dk)
1. `app/api/setup.py` (yukarıdaki şablon, 6 endpoint + state machine + `_persist_env_var` helper)
2. `app/main.py` — `setup_router` register
3. `tests/test_setup_wizard.py` (7 test, monkeypatch tmp_path data_dir, JWT fixture)
4. `pytest tests/test_setup_wizard.py -v` → 7 PASS

### 3. Modul B — First-Run Middleware (30 dk)
1. `app/middleware/__init__.py` + `app/middleware/first_run.py` (yukarıdaki şablon)
2. `app/main.py` — `add_middleware(FirstRunMiddleware)` (en üstte — diğer middleware'lerden önce)
3. `tests/conftest.py` — autouse fixture: `setup_state.json` `completed:true` yaz (mevcut testler bozulmasın)
4. `tests/test_first_run_middleware.py` (4 test, izole tmp_path setup state)
5. `pytest tests/test_first_run_middleware.py tests/test_panel.py tests/test_license_api.py -v` → tüm geri kalan testler hâlâ yeşil

### 4. Modul C — Setup UI (40 dk)
1. `app/static/setup/index.html` (yukarıdaki şablon, 6 step section + logo + tagline)
2. `app/static/setup/assets/setup.css` (brand token reuse)
3. `app/static/setup/assets/setup.js` (state machine, fetch, error handling)
4. `app/main.py` — static mount `/setup/assets/` + `GET /setup` index serve
5. `tests/test_setup_ui.py` (2 test)
6. `pytest tests/test_setup_ui.py -v` → 2 PASS

### 5. Modul D — Panel Demo Countdown Banner (30 dk)
1. `app/static/panel/index.html` patch — `demo-banner` div ekle
2. `app/static/panel/assets/panel.css` patch — `.demo-banner` + `.demo-warn` + `.demo-danger`
3. `app/static/panel/assets/panel.js` patch — `addEventListener('license-status', ...)` handler
4. `tests/test_panel_banner.py` (3 test, file content assertions)
5. `pytest tests/test_panel_banner.py -v` → 3 PASS

### 6. Modul E — Email Templates + Refund Integration (30 dk)
1. `app/email/templates/license_refund.html` (mevcut delivery template'i baz al, brand-uyumlu)
2. `app/email/templates/license_expired.html`
3. `app/email/sender.py` — `send_refund_email`, `send_expiration_email` fn'ları
4. `app/api/webhooks/stripe.py` — refund handler'da `send_refund_email` çağrısı (try/except sessiz)
5. `tests/test_email_templates.py` (3 test)
6. `pytest tests/test_email_templates.py tests/test_stripe_webhook.py -v` → mevcut 4 + yeni 3 = 7 PASS

### 7. Modul F — MCP Tool setup_status (15 dk)
1. `app/mcp/tools/setup_tools.py` (1 tool)
2. `app/mcp/server.py` Read → tam Write override (setup_tools import + count)
3. `tests/test_tools_count.py` patch (91 → 92, `setup_status` must_have)
4. `pytest tests/test_tools_count.py -v` → 2 PASS

### 8. Tam Test Suite (5 dk)
```bash
.venv/bin/pytest -q
# 178+ passed
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 92
```

### 9. Live MCP Smoke (15 dk)

uvicorn boot + manuel browser test (kullanıcı yapar):
1. Setup state SİL: `rm /tmp/abs-data/setup_state.json` (veya tmp data_dir)
2. `uvicorn app.main:app --port 8765 &`
3. `curl http://localhost:8765/panel` → 302 → location `/setup` ✓
4. `curl http://localhost:8765/healthz` → 200 ✓ (whitelist)
5. `curl http://localhost:8765/setup` → 200 + HTML ✓
6. `claude mcp add abs-012 http://localhost:8765/mcp/ --transport http`
7. 4 canlı kanıt JSON → `/tmp/abs-012-smoke/evidence/`:
   - `setup_status` → `{"completed":false,"current_step":1,"completed_steps":[]}`
   - GET `/v1/setup/status` REST karşılaştırma
   - POST `/v1/setup/step/admin` `{email,password}` → 200 + `current_step:2`
   - GET `/setup` HTML → `data-step="1"` içerir

### 10. Tamamlama
1. `_agent-tasks/completed/012-setup-wizard-onboarding.md` taşı
2. `012-setup-wizard-onboarding-summary.md` yaz:
   - 6 modül + dosya listesi
   - Test sonuçları (158 → 178+)
   - 4 smoke kanıtı
   - Notlar Planlayıcıya

## Doğrulama (Worker fail-fast)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                                # 178+ passed
.venv/bin/pytest tests/test_tools_count.py -v                      # 92 guard
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 92
.venv/bin/python -c "from app.api.setup import read_state; print(read_state())"
# {'completed': False, 'current_step': 1, ...} (state yoksa init)
```

## Notlar Planlayıcıya (Worker doldursun)

- **Encrypted secrets (age/sops)** 012'de **YOK** — API key'ler plaintext `.env`'de. 013'e bırakıldı (vault module + master key UX).
- **Setup wizard UI**: vanilla HTML/JS — framework yok. Brand uyumlu mavi küp logo + tagline + 6-step indicator. Refactor 013'te (Alpine.js veya SvelteKit micro-app) düşünülebilir.
- **Admin credentials file** `data_dir/admin_credentials.json` — MVP. Production'da DB-backed user table + multi-user 014+'a.
- **Setup completed sonrası middleware no-op** — performance OK (her istekte file-stat var, 0.1ms civarı). 015+'da in-memory cache opt-in.
- **Refund email opsiyonel** — SMTP yapılandırılmadıysa console log fallback. Müşteri panel'den email konfigüre eder (014?).
- **Provider test (adım 6)**: her configured provider'a 1 ping çağrı (max 5sn timeout). Cohere yoksa skip. Test sonuçları `setup_state.json::data.test_results` altında.
- **First-run + login race**: Setup tamamlanmadıysa `/auth/login` whitelist DIŞINDA — kullanıcı setup yapmadan login'e gidemiyor. Setup tamamlanınca `/auth/login` 302 değil 200. Bu bilinçli.

## Kapsam Dışı (013+'a)

- Encrypted secrets (age/sops) vault — 013
- Multi-user auth + RBAC — 014+
- Setup wizard React/Svelte refactor — 014+
- Provider key rotation UI (panel) — 013
- Audit log (kim ne zaman setup yaptı) — 014
- Update Channel + Watchdog — 013 (önceki sıralamada A yönüydü)
- Stripe Customer Portal — 014+
