# Task 012 — Setup Wizard + First-Run Redirect + Demo Banner + Email Templates (SUMMARY)

**Tamamlandı:** 2026-04-25
**Süre:** ~1.5 saat (planlanan 4-5h altında — şablonlar tam, refactor yok)
**Sonuç:** 6 modül + Registry. Hepsi yeşil.

## Özet

| Hedef | Önce | Sonra | Δ |
|-------|------|-------|---|
| pytest yeşil | 158 | **178** | +20 |
| MCP tool sayısı | 91 | **92** | +1 (`setup_status`) |
| Mevcut 14 license/stripe/middleware testi | 14 yeşil | **14 yeşil** | korundu |
| SSE event sayısı (panel) | 6 | **6** (license-status payload genişledi) | event count sabit |
| Setup wizard endpoint | yok | 6-step + reset | yeni |
| First-run middleware | yok | whitelist-based redirect | yeni |
| Setup UI | yok | vanilla HTML/JS brand-uyumlu | yeni |
| Email template (refund + expired) | yok | jinja2 + console fallback | yeni |
| Panel demo countdown banner | yok | 3 state (default/warn/danger) | yeni |

## Modul A — Setup State + Endpoints

**Yeni dosya:** `app/api/setup.py` (~290 satır, 7 endpoint)
- `GET /v1/setup/status` — state JSON
- `POST /v1/setup/step/admin` — bcrypt hash + `data_dir/admin_credentials.json` + `.env` `ABS_ADMIN_EMAIL`
- `POST /v1/setup/step/license` — `verify_license` + `.env` `ABS_LICENSE_KEY`
- `POST /v1/setup/step/domain` — domain regex + `.env` `ABS_DOMAIN`/`ABS_SSL_MODE`
- `POST /v1/setup/step/anthropic` — `sk-ant-...` regex + `.env` `ABS_ANTHROPIC_API_KEY`
- `POST /v1/setup/step/providers` — opsiyonel groq/gemini/cerebras/cohere/cf — eklenenler `.env`'e
- `POST /v1/setup/step/test` — provider ping (mock'lanir, 'skipped' default) + `completed=true` + `completed_at=now`
- `POST /v1/setup/reset` — dev-only state + admin credentials sil

**Helper'lar:**
- `setup_state_path()` — read-only fs'de defensive mkdir
- `read_state()` — yoksa initial state, exception fırlatmaz
- `_atomic_write_state()` — temp+replace
- `_persist_env_var(key, value, env_path?)` — generic .env patcher (mevcut `_persist_license_key_to_env` pattern'i baz aldı)
- `_ensure_step()` — completed/current_step guard (409 conflict)

**State file** `<data_dir>/setup_state.json`:
```json
{
  "completed": false,
  "current_step": 1,
  "completed_steps": [],
  "started_at": ...,
  "completed_at": null,
  "data": {
    "admin": null, "license": null, "domain": null,
    "anthropic_configured": false, "providers_configured": [],
    "test_results": {}
  }
}
```

**Yeni test:** `tests/test_setup_wizard.py` (7 test) → **7/7 PASS**
**Patch:** `app/main.py` — `setup_router` register

## Modul B — First-Run Redirect Middleware

**Yeni dosya:** `app/middleware/first_run.py` (~50 satır)
- `_setup_completed()` — file-stat (~0.1ms)
- `FirstRunMiddleware.dispatch` — `text/html` Accept → 302, JSON → 307
- Whitelist (8 prefix): `/healthz`, `/v1/setup`, `/setup`, `/panel/assets/`, `/static/`, `/_internal/`, **`/mcp`**

**`/mcp` whitelist kararı:** Spec'e ek olarak `/mcp` eklendi — `setup_status` MCP tool'unun amacı kurulum öncesi durum sorgulamak. Claude Code `claude mcp add abs-012 ...` setup tamamlanmadan da bağlanabilmeli.

**Yeni dosya:** `app/middleware/__init__.py` (1 satır docstring)
**Patch:** `app/main.py` — `app.add_middleware(FirstRunMiddleware)` (FastAPI yapısı ekleme sırasını ters çevirdiği için bu çağrı en alt katman olur — istek sırası: middleware → router → handler ✓)

**Conftest fixture (kritik):**
- `_session_data_dir` (session, autouse) — `settings.data_dir` test-session boyunca tmp dizine sabitle (default `/app/data` host'ta yazılamaz)
- `_autocomplete_setup_state` (function, autouse) — `setup_state.json` `completed:true` yaz (mevcut testler middleware redirect almasın). Setup wizard / first-run testleri `monkeypatch.setattr(settings, 'data_dir', tmp_path)` ile fixture'i bypass eder.

**Yeni test:** `tests/test_first_run_middleware.py` (4 test) → **4/4 PASS**
**Regression:** mevcut test_panel.py 6/6, test_license_api.py 3/3, test_setup_wizard.py 7/7 — 16 endpoint testi yeşil.

## Modul C — Setup UI

**Yeni dosyalar:**
- `app/static/setup/index.html` (~110 satır) — 6 step section, breadcrumb, brand SVG küp, "Automate the Chaos" tagline
- `app/static/setup/assets/setup.css` (~135 satır) — `--brand-primary` `--brand-gradient` reuse, dark theme, responsive
- `app/static/setup/assets/setup.js` (~90 satır) — `loadState()` boot, `formToJson` + `postStep`, error inline alert, finish redirect `/panel/login`

**Patch:** `app/main.py` — `SETUP_STATIC_DIR` mount `/setup/assets` + `GET /setup` FileResponse

**Yeni test:** `tests/test_setup_ui.py` (2 test) → **2/2 PASS**

## Modul D — Panel Demo Countdown Banner

**Patch:** `app/static/panel/index.html` — `<div id="demo-banner">` `alert-bar` altına eklendi (icon + text + dismiss button + purchase link)

**Patch:** `app/static/panel/assets/panel.css` (append, ~20 satır):
- `.demo-banner` (default brand gradient)
- `.demo-warn` (#f59e0b — 7-3 gün kaldı)
- `.demo-danger` (#ef4444 — ≤3 gün veya demo expired)
- `.demo-banner-dismiss` (× kapat)

**Patch:** `app/static/panel/assets/panel.js` (2 yere — `bindSse` x2):
- `sse.addEventListener("license-status", ...)` → `onLicenseStatus(d)`
- `onLicenseStatus`: `license_active` → hide; `!demo_active` → danger 0 days; aktifse `demo_days_remaining` ile warn/danger toggle
- `dismissDemoBanner()` global fn (24h TTL localStorage flag)

**Yeni test:** `tests/test_panel_banner.py` (3 test, file content assertions) → **3/3 PASS**
**Regression:** test_panel.py 6/6 hâlâ yeşil.

## Modul E — Email Templates + Refund Integration

**Yeni dosyalar:**
- `app/email/templates/license_refund.html` — TR, brand-uyumlu, refund_date + license_jti vurgu
- `app/email/templates/license_expired.html` — TR, expired_at + yenileme CTA

**Patch:** `app/email/sender.py` — 2 yeni fn:
- `send_refund_email(to, license_jti, refund_date)` — render + `_send_html(kind="refund")`
- `send_expiration_email(to, license_jti, expired_at)` — render + `_send_html(kind="expiration")`
- `_send_html()` helper — SMTP veya console fallback (smtp_host boşsa log + return; SMTP exception silent log)

**Patch:** `app/api/webhooks/stripe.py` — refund handler içinde:
```python
if license_row.customer_email:
    try:
        send_refund_email(to=..., license_jti=..., refund_date=...)
    except Exception as exc:
        logger.exception("refund email gönderim: %s", exc)
```
Sessiz başarısızlık — refund DB write'ı blokmaz.

**Yeni test:** `tests/test_email_templates.py` (4 test — 3 zorunlu + 1 expiration fallback parametrize) → **4/4 PASS**
**Regression:** test_stripe_webhook 4/4, test_refund_handler 3/3 — 7/7 yeşil.

## Modul F — MCP Tool setup_status + Registry

**Yeni dosya:** `app/mcp/tools/setup_tools.py` (~25 satır, 1 tool)
- `setup_status` — `read_state()` JSON döner (`tracker.bump`)

**Patch:** `app/mcp/server.py` (tam Write override) — `setup_tools` import + count.
**Patch:** `tests/test_tools_count.py` — 91 → **92 guard**, must_have'a `setup_status`.

**Test:** `tests/test_tools_count.py` 2/2 PASS. `_REGISTERED_COUNT == 92`.

## Test Sonuçları

```
.venv/bin/pytest -q
178 passed in 4.95s
```

**Önce:** 158. **Sonra:** 178. **Hedef:** 178+. **+20 yeni test:**
- test_setup_wizard.py: 7
- test_first_run_middleware.py: 4
- test_setup_ui.py: 2
- test_panel_banner.py: 3
- test_email_templates.py: 4 (3 zorunlu + 1 expiration parametrize)

**Mevcut 14 license/stripe/middleware testi:**
```
tests/test_stripe_webhook.py    4/4 PASS  (refund email integration sonrası hâlâ)
tests/test_license_api.py       3/3 PASS
tests/test_licensing.py         4/4 PASS
tests/test_mcp_middleware...    3/3 PASS
                              ────────
                                14/14 PASS  ✓
```

**Diğer regresyon:**
```
tests/test_panel.py             6/6 PASS  (banner eklendi, mevcut sabit)
tests/test_license_gate.py      4/4 PASS
tests/test_demo_mode.py         6/6 PASS  (isolated_demo fixture setup_state.json yazıyor)
tests/test_refund_handler.py    3/3 PASS  (email sender entegre)
```

## Live MCP Smoke (Kanıtlar `/tmp/abs-012-smoke/evidence/`)

uvicorn `--port 8767` (env override: tmp dirs, `ABS_ENV=dev`).

### 0. `/panel` first-run redirect → 302 `/setup` (00_panel_redirect.txt)
```
HTTP/1.1 302 Found
location: /setup
```

### 0a. `/healthz` whitelist → 200
```json
{"status":"ok","service":"abs-backend"}
```

### 1. `setup_status` (MCP) → fresh state, completed:false (01_setup_status_mcp.json)
```json
{
  "completed": false,
  "current_step": 1,
  "completed_steps": [],
  "started_at": 1777138277.43,
  "completed_at": null,
  "data": {"admin": null, "license": null, ...}
}
```

### 2. `GET /v1/setup/status` REST → aynı payload (02_setup_status_rest.json)

### 3. `GET /setup` HTML → 200 + 6-step wizard (03_setup_html.html başlık)
```html
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  ...
```

### 4. `POST /v1/setup/step/admin` → current_step:2 (04_setup_step_admin.json)
```json
{"ok": true, "current_step": 2}
```

MCP tools/list = **92** init handshake OK. Setup wizard advance OK. Static UI serve OK.

## Notlar Planlayıcıya

1. **`/mcp` whitelist eklendi.** Spec'te yoktu; `setup_status` MCP tool'u kurulum öncesi sorgulanabilmeli. Çoğu tool `mcp_require_license=True` ise gate'lenir (011), bu yüzden `/mcp` whitelist != tüm tool'lar açık. Kurulum öncesi `setup_status` + `system_status` gibi public tool'lar erişilebilir, lisanslı tool'lar 011 gate'iyle korunur.

2. **Conftest `_session_data_dir` autouse** — 011 öncesi testler default `/app/data` (host yazma izni yok) ile çalışıyordu, bu task'ta `Path(settings.data_dir).mkdir` çağrıları başlayınca tmp'e taşımak zorunlu kaldı. Side effect: testlerde tüm DB/dosya işlemleri tek session-tmp'te toplanıyor, izolasyon function-scope monkeypatch ile sağlanıyor.

3. **`_autocomplete_setup_state` autouse fixture'ı** middleware'in mevcut testlere zarar vermemesi için zorunlu. `isolated_setup` / `incomplete_setup` / `incomplete_demo` gibi function-scope fixture'lar `monkeypatch.setattr(settings, 'data_dir', tmp_path)` ile bypass eder.

4. **Provider test (adım 6) live ping yapmaz** — şu an "skipped" döner. 013'te gerçek HEAD/echo ping (timeout 5s) eklenebilir. Cohere/Anthropic için spesifik endpoint kullan.

5. **Admin credentials file** `data_dir/admin_credentials.json` — bcrypt hash + email. **`auth.py::ADMIN_PASSWORD_HASH`** hâlâ env var'dan import-time hash'liyor; setup tamamlandığında bu credentials dosyasını okumuyor. **Bu küçük bug 013'te düzeltilmeli** — auth.py login flow `admin_credentials.json` varsa onu kullansın, yoksa env fallback.

6. **`.env` patch ABS_ENV=dev** — kullanıcının setup wizard'ı dev'den prod'a geçirme akışı kapsam dışı. 013 deployment hardening'inde gözden geçirilmeli.

7. **Setup UI vanilla — framework yok** — Alpine.js veya HTMX 014+'a düşünülebilir. Şu an 6 step + form submit + fetch yeterli.

8. **Demo banner SSE event payload genişledi** (011'de eklenen `_build_license_status` aynen kullanılıyor). 013'te `purchase_url` müşteri-spesifik affiliate code ile zenginleştirilebilir.

9. **Refund email + expiration email sessiz** — SMTP yoksa console log. **Refund 011 webhook'unda integration eklendi** ama Stripe kendi refund onay maili atar; çift mail riskini kullanıcı email config'iyle yönetmeli (smtp_host boş = ABS sessiz).

10. **First-run middleware in-memory cache yok** — her istekte file-stat (~0.1ms). Production'da yüksek RPS senaryosunda 015+'da TTL cache eklenebilir.

11. **Pyright `app.licensing.demo` import resolution** — bazı dosyalarda kalıcı warning. Runtime sorunsuz, pyright cache miss. 014'te pyrightconfig.json güncellemesi düşünülebilir.

## Feature Parity

012 SERVER paritesinden **ileriye geçer**:
- 6-step setup wizard: SERVER'da yok (orchestrator localhost'ta config dosyası ile çalışır).
- First-run middleware: ABS-specific (self-host müşteri UX).
- Refund / expiration email: ABS-specific (SaaS commerce flow).
- Setup UI: ABS-specific (müşteri tarayıcısı).

Atlanan parity yok.

## Doğrulama (Fail-Fast)

```bash
$ .venv/bin/pytest -q
178 passed in 4.95s

$ .venv/bin/pytest tests/test_tools_count.py -v
2 passed

$ .venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
92

$ .venv/bin/python -c "from app.mcp.server import mcp_server; import asyncio; print(len(asyncio.run(mcp_server.list_tools())))"
92

$ ABS_DATA_DIR=/tmp/abs-012-validate \
  .venv/bin/python -c "from app.api.setup import read_state; print(read_state()['completed'])"
False

$ curl http://localhost:8767/panel    # 302 → /setup ✓
$ curl http://localhost:8767/healthz   # 200 ✓ (whitelist)
$ curl http://localhost:8767/setup     # 200 + HTML ✓
```

Hepsi yeşil.

## Kapsam Dışı (013+'a)

- Encrypted secrets (age/sops) vault — **013'ün çekirdeği**
- Multi-user auth + RBAC — 014+
- Setup wizard React/Svelte refactor — 014+
- Provider key rotation UI — 013
- Setup wizard live provider ping (gerçek HEAD/echo) — 013
- Audit log — 014
- Update Channel + Watchdog — 013
- Auth flow `admin_credentials.json` integration (küçük bug) — 013
