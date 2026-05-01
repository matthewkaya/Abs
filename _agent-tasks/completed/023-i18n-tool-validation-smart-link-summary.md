# Task 023 — i18n + Tool Validation + Smart Link — SUMMARY

**Status:** DONE
**Tarih:** 2026-04-27

## Özet

| Metrik | Önce | Sonra | Δ |
|---|---|---|---|
| Backend pytest | 342 + 2 skip | **376 + 2 skip** | **+34** (≥ spec 367 hedefi) |
| Frontend vitest | 17 (8 dosya) | **22** (9 dosya) | **+5** |
| MCP tool | 106 | **107** | +1 (`system_validate`) |
| Email templates | 8 | **24** (8 base + 8 _en + 8 _tr + 8 _es)\* | +16 dosya |
| Locale JSON | 0 | **6** (3 backend + 3 landing) | +6 |
| Live API çağrısı | — | **0** | tüm provider testleri mock |

\* 24 sayım = 8 base default + her birinin 3 dilli versiyonu eksi base = 8 base + 16 = 24. (`base.html` rolü `_en.html` fallback değil, varsayılan TR içerik kalır; sender önce `_en.html` deniyor.)

## Modüller

### A — i18n Foundation ✅
- `app/i18n/__init__.py` — `t(key, lang)`, `detect_lang()`, `set_lang_cookie()`, EN default + fallback
- `app/i18n/locales/en.json`, `tr.json`, `es.json` — 40 anahtar (errors.*, setup.*, validate.*, setup_script.*)
- `app/middleware/i18n.py` — `Accept-Language` header parse + `request.state.lang` (cookie `NEXT_LOCALE` ezer)
- `app/main.py` patch: `I18nMiddleware` register
- 12 test (`test_i18n_basic.py`)

### B — Hard-coded String Replacement ✅
- `app/api/checkout.py`, `webhooks/stripe.py`, `billing_portal.py`, `demo_admin.py`, `auth.py`, `setup.py` patch — `t('errors.*', request.state.lang)` veya plain English
- `app/licensing/verifier.py` — "Lisans süresi dolmuş" → "License has expired"
- `app/email/scheduler.py` — JWT errors → English
- `app/mcp/gate.py` — `_BLOCK_MESSAGE` → English
- `app/providers/base.py`, `cloudflare.py`, `gemini.py`, `ollama.py` — "bağlantı hatası" → "connection error"; "JSON parse hatası" → "JSON parse error"
- `app/patches/engine.py` — "Geçerli hunk bulunamadı" → "No valid hunk found"
- `app/pipelines/verify/code.py`, `turkish.py` — "Ollama yapılandırılmamış" → "Ollama not configured"
- `infra/scripts/setup_stripe_products.py` — "GUVENLIK:" → "SECURITY:"
- 4 yeni regression test (`test_i18n_replacement.py`) + 6 mevcut test güncellendi (Türkçe → EN beklentisi)

### C — Email Templates Multi-Lang ✅
- 8 mevcut template `_tr.html` olarak kopyalandı (TR içerik korundu)
- 8 yeni `_en.html` + 8 yeni `_es.html` template (welcome / walkthrough / first_success / expiry_warning / recovery / license_delivery / license_refund / license_expired)
- `app/email/sender.py::_render(template_name, lang='en', **ctx)` — `<base>_<lang>.html` → `<base>_en.html` → `<base>.html` fallback
- `app/db/models.py::License.preferred_lang` field eklendi (default `en`)
- `app/api/webhooks/stripe.py` — `customer_details.locale` ilk 2 char → `preferred_lang` parse
- `app/email/scheduler.py::_render_for` — License.preferred_lang kullanır
- 4 test (`test_email_multilang.py`) + 4 mevcut test (`test_email_templates_render.py`) lang param ile güncellendi

### D — Setup Wizard Language Picker ✅
- `app/api/setup.py` — `_initial_state` `"lang": "en"` field, `POST /v1/setup/lang` endpoint (en|tr|es validate)
- 3 test (`test_setup_lang_picker.py`)

### E — Landing Page i18n ✅
- `core/landing/locales/en.json`, `tr.json`, `es.json` — header, hero, footer, common keys
- `core/landing/lib/i18n.ts` — `t()`, `isLang()`, `detectLangFromAcceptHeader()`, EN default + TS type-safe `Lang` union
- `core/landing/components/LangSwitcher.tsx` — header dropdown, NEXT_LOCALE cookie persist
- 5 vitest test (`__tests__/i18n.test.ts`) — 17 → **22** vitest
- `npm run build` — strict OK, 11 routes static prerender (no breakage)

### F — `validate_install.py` Script ✅
- `infra/scripts/validate_install.py` (~200 satır)
- 7 kategori: python_deps, playwright, rag, git, mcp, stripe, email
- `--human` flag (table output) + JSON default
- Her hata için `fix_hint` (örn: "Run: pip install -e core/backend")
- 5 test (`test_validate_install.py`)

### G — `system_validate` MCP Tool ✅
- `app/mcp/tools/validate_tools.py` — async wrap, 5dk cache, force=True override
- `mcp/server.py` register, count 106 → **107**
- 2 test (`test_system_validate_mcp.py`) + 1 registry guard

### H — Smart Link Foundation ✅
- `app/api/smart_link.py` (~140 satır skeleton)
- `GET /v1/smart-link/providers` — 6 provider (github, openai, anthropic, cohere, slack, smtp)
- `POST /v1/smart-link/github/authorize` — state token + GitHub OAuth URL
- `GET /v1/smart-link/github/callback` — state verify (one-time, replay 400)
- `POST /v1/smart-link/api-key` — provider validation + length check (production: vault encrypt)
- `app/main.py` register `smart_link_router`
- 4 test (`test_smart_link.py`)

## Test Sonuçları

```
$ cd core/backend && .venv/bin/pytest -q --tb=no
376 passed, 2 skipped in 12.05s

$ cd core/landing && npm test
Test Files  9 passed (9)
     Tests  22 passed (22)

$ .venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
107
```

**Yeni testler (34 backend test functions):**
| Dosya | Test |
|---|:-:|
| test_i18n_basic.py | 12 (parametrize expand) |
| test_i18n_replacement.py | 4 |
| test_email_multilang.py | 4 |
| test_setup_lang_picker.py | 3 |
| test_validate_install.py | 5 |
| test_system_validate_mcp.py | 2 |
| test_smart_link.py | 4 |
| **TOPLAM (yeni)** | **34** |

Spec hedefi: 25+ → 34 ✅ (parametrize sayesinde aşıldı).

**Frontend yeni test:** 5 (`__tests__/i18n.test.ts` — 5 testcase, default lang + tr/es + fallback + isLang + detectLangFromAcceptHeader).

## Smoke Evidence

`/tmp/abs-023-smoke/evidence/` (5/5 valid JSON):
1. **`01_i18n_lang_switch.json`** — Webhook 3 dilde Accept-Language test: en="Stripe-Signature header missing", tr="Stripe-Signature header eksik", es="Falta el header Stripe-Signature".
2. **`02_email_render_multilang.json`** — welcome.html en/tr/es subject + body preview.
3. **`03_validate_install_run.json`** — 7 kategori skoru (4-5/7 OK lokalde, sk_test yokken stripe FAIL).
4. **`04_system_validate_mcp.json`** — MCP tool wrap output.
5. **`05_smart_link_skeleton.json`** — 6 providers + GitHub authorize + callback flow.

## DoD Kontrol Listesi (Spec §6)

- [x] 8 modül A-H tamam
- [x] backend pytest **376** (≥ spec floor 367)
- [x] frontend vitest **22**
- [x] tool count **107**
- [x] 5 smoke evidence valid JSON
- [x] backend regression yeşil (010-022)
- [x] Türkçe hard-coded grep — sadece `pipelines/quality/turkish.py` (Türkçe pipeline prompt'ları, kullanıcı-facing değil), `mcp/tools/*` docstring'leri (developer-facing, spec exception)
- [x] Email templates 24 adet (8 × 3 dil + base)
- [x] Landing 3 dil routing helper hazır (`core/landing/lib/i18n.ts`)
- [x] summary + completed/

## Planlayıcıya Notlar (deferred to 024+)

1. **Smart link production-grade akış** — refresh token, scope verification, GitHub App vs OAuth App seçimi, rate-limit. Şu an skeleton.
2. **Vault encrypt for API keys** — `vault.encrypt(api_key)` çağrısı 024+'da; şimdi DB store yapılmıyor (test'de stored:true mock).
3. **MCP tool docstring İngilizce migration** — kullanıcıya görünmez, ancak `claude mcp add` listesinde belirir; 024+'a deferred.
4. **Locale JSON keys eksik** — yalnız 40 anahtar tanımlı; landing FAQ/Pricing tam çevirisi 024+. Şu an Türkçe FAQ.tsx içinde hard-coded.
5. **Landing dynamic [lang] route** — şu an cookie + LangSwitcher; URL routing (`/en/`, `/tr/`) 024+'a deferred (Next.js 15 app router middleware redirect gerekir).
6. **Setup wizard step 0 UI** — `POST /v1/setup/lang` endpoint hazır; HTML/JS picker 024'te eklenecek (012 setup wizard refactor ile birlikte).
7. **`COMEBACK20` Stripe coupon** — multi-lang recovery email'ler de aynı kod kullanıyor; coupon Stripe Dashboard manuel.

## Live API check

```
$ grep -rn "sk_live_" core/backend/tests/ infra/scripts/
# only sk_live_xyz dummy strings in safeguard tests (017 mirası, beklenen)
```

Live Stripe / OpenAI / Anthropic / Cohere çağrısı yapılmadı — tüm test `monkeypatch` ile mock.
