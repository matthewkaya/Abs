# Task 023 — i18n + Tool Validation + Smart Link Foundation

**Status:** READY (Worker autonomous mode)
**Tahmini süre:** 4-6 saat
**Bağımlı task'lar:** 010-022 hepsi (özellikle 011 Stripe, 012 Setup Wizard, 018 Landing, 019 Email)
**Bağlam:**
- `feedback_product_global_first.md` (memory) — ürün İngilizce default + TR/ES seçenek
- `feedback_product_tool_validation.md` (memory) — Playwright/RAG/git/MCP tool çalışırlık + smart link

**Hedef sonuç:**
1. **Ürün globale satılabilir hale gelsin** — varsayılan İngilizce, TR + ES alternatif locale.
2. **Müşteri kurulumda hiçbir tool kırık olmasın** — runtime validation + fix hint.
3. **Smart link foundation** — müşteri GitHub/OpenAI/Anthropic vb. servisleri akıllıca bağlasın (skeleton, production-grade 024+).

---

## 0. Kritik Bağlam (önce oku)

`feedback_product_global_first.md`'de listelenmiş **mevcut Türkçe hard-coded strings**:
- `app/api/checkout.py` "Stripe yapılandırılmadı" → "Stripe not configured"
- `app/api/license.py` "süresi dolmuş" → "expired"
- `app/api/webhooks/stripe.py` "Stripe-Signature header eksik" → "missing"
- `app/email/templates/*.html` (en az 8 template)
- `app/mcp/gate.py` `_BLOCK_MESSAGE` "[LISANS GEREKLI]" → "[LICENSE REQUIRED]"
- `infra/scripts/setup_stripe_products.py` "GUVENLIK:", "ABORT" mesajları
- `app/providers/*.py` ("bağlantı hatası", "JSON parse hatası") — anthropic, gemini, cloudflare, ollama, base
- `app/patches/engine.py` ("Geçerli hunk bulunamadı")
- `app/pipelines/verify/code.py` ("Ollama yapılandırılmamış")
- 020 docs (billing-runbook, first-customer-playbook) — sadece TR yazılmış, EN gerekli
- 012 setup wizard 6 adım metinleri

**Kapsam dışı:** İç MCP tool docstring'leri (developer-facing, EN olabilir ama mevcut TR yorumları bırakılabilir — kullanıcıya görünmez).

---

## 1. Amaç (DoD)

- [ ] `app/i18n/` modülü: 3 locale JSON + translator + middleware
- [ ] Backend Türkçe hard-coded mesajlar `t(key, lang)` çağrısına dönüştürüldü
- [ ] Email template'leri 3 dilli (`*_en.html`, `*_tr.html`, `*_es.html`)
- [ ] Setup wizard 1. adım: dil seçici (`en` default, browser auto-detect)
- [ ] Landing page (`core/landing/`) Next.js i18n routing 3 dil
- [ ] `infra/scripts/validate_install.py` — tool health check + fix hint
- [ ] MCP tool `system_validate` — runtime tool health (104 → 107)
- [ ] `app/api/smart_link.py` — GitHub OAuth + API key bağlantı endpoint'leri (skeleton)
- [ ] 25+ yeni test, pytest 342 → ~367
- [ ] 5 smoke evidence

---

## 2. Modüller

### Modul A — i18n Foundation
**Yeni:**
- `app/i18n/__init__.py` — `t(key, lang='en')`, `detect_lang(accept_language_header)`, `set_lang(response, lang)` cookie helper
- `app/i18n/locales/en.json`, `tr.json`, `es.json` — initial keys (~40-60 anahtar):
  - `errors.stripe_not_configured`
  - `errors.signature_missing`
  - `errors.license_expired`
  - `errors.license_required`
  - `errors.provider_connection`
  - `errors.json_parse`
  - `errors.ollama_not_configured`
  - `errors.patch_invalid_hunk`
  - `setup.welcome`, `setup.step_N_title`, vb.
- `app/middleware/i18n.py` — `Accept-Language` parse + request.state.lang
- 3 test (`test_i18n_basic.py`)

### Modul B — Hard-coded String Replacement
- `app/api/checkout.py`, `license.py`, `webhooks/stripe.py` patch
- `app/providers/anthropic.py`, `gemini.py`, `cloudflare.py`, `ollama.py`, `base.py` patch
- `app/patches/engine.py`, `app/pipelines/verify/code.py` patch
- `app/mcp/gate.py` `_BLOCK_MESSAGE` → `t('errors.license_required', lang)`
- `infra/scripts/setup_stripe_products.py` print mesajları → en string + (--lang flag opsiyonel, default en)
- 4 regression test (mevcut path'ler hâlâ doğru status_code döner, mesaj sadece dil değişmiş)

### Modul C — Email Templates Multi-Lang
- 8 mevcut template her biri için `_en.html`, `_tr.html`, `_es.html` versiyonları
- `app/email/sender.py` patch — `_render(template_name, lang='en')` (template_name + suffix lookup)
- License DB'ye `preferred_lang` kolon (default `en`)
- Webhook `checkout.session.completed` Stripe Customer locale'i okuyor mu? (yoksa default en)
- 4 test

### Modul D — Setup Wizard Language Picker
- `app/api/setup.py` — wizard step 0 yeni: dil seçimi (en/tr/es radio + browser auto-detect)
- `data/setup_state.json` `lang` field
- 3 test

### Modul E — Landing Page i18n
- `core/landing/next.config.ts` — i18n routing config
- `core/landing/app/[lang]/page.tsx` — dynamic route
- `core/landing/locales/en.json`, `tr.json`, `es.json`
- `core/landing/components/Header.tsx` patch — dil seçici dropdown
- Cookie persist (NEXT_LOCALE)
- 5 component test (vitest)

### Modul F — `validate_install.py` Script
**Yeni:** `infra/scripts/validate_install.py` (~250 satır):
- 7 kategori check:
  1. Python venv + dependencies (`stripe`, `sqlmodel`, `fastapi`, `chromadb`, `cohere`, `cryptography`)
  2. Playwright (`npx playwright install --dry-run` veya browser path check)
  3. RAG (chromadb daemon + index var mı)
  4. Git (`git config user.email` + `user.name` var mı)
  5. MCP server (`mcp_server.list_tools()` boot OK)
  6. Stripe (env var + `stripe.Account.retrieve` mock)
  7. Email (SMTP_HOST set mi veya console fallback OK)
- Output: JSON `{tool: {ok: bool, error: str | null, fix_hint: str | null}}`
- 5 test (`test_validate_install.py`)

### Modul G — `system_validate` MCP Tool
**Yeni:** `app/mcp/tools/validate_tools.py`:
- `system_validate()` — Modul F'deki validate_install'i async wrap eder
- Cache 5dk (tool zincir çağrılarında DB hit'e gerek yok)
- 2 test
- Tool count 106 → **107**

### Modul H — Smart Link Foundation
**Yeni:** `app/api/smart_link.py` (~150 satır, skeleton):
- `GET /v1/smart-link/providers` — desteklenen entegrasyonlar listesi (GitHub, OpenAI, Anthropic, Cohere, Slack, SMTP)
- `POST /v1/smart-link/github/authorize` — OAuth start (state + redirect URL)
- `GET /v1/smart-link/github/callback` — code → token → DB store (encrypted via vault)
- `POST /v1/smart-link/api-key` — provider + api_key body, validate (provider-specific test call), DB store encrypted
- 4 test (mock OAuth flow, mock validate, encrypt/decrypt roundtrip)
- **NOT:** Production-grade flow değil (rate-limit, refresh token, scopes, vb. 024+'a)

---

## 3. Test Stratejisi (25+ test)

| Modül | Test |
|---|:-:|
| A i18n | 3 |
| B replacement (regression) | 4 |
| C email multi-lang | 4 |
| D wizard lang picker | 3 |
| E landing i18n (vitest, frontend ayrı sayılır) | 5 |
| F validate_install.py | 5 |
| G system_validate MCP | 2 |
| H smart_link | 4 |
| Tool count guard | (1 update) |
| **TOPLAM** | **25 backend + 5 frontend** |

Backend: 342 → **367** (+25). Frontend: 17 → **22** (+5).

---

## 4. Smoke Evidence (`/tmp/abs-023-smoke/evidence/`)

1. `01_i18n_lang_switch.json` — 3 dilde aynı endpoint farklı response
2. `02_email_render_multilang.json` — 3 dilde welcome.html render
3. `03_validate_install_run.json` — script tam run output
4. `04_system_validate_mcp.json` — MCP tool response
5. `05_smart_link_skeleton.json` — providers list + mock github callback

---

## 5. Adım Adım

```
1.  baseline pytest 342 + tool 106
2.  Modul A: i18n module + 3 locale + middleware + 3 test
3.  Modul B: hard-coded replacement (paralel dosyalar) + 4 regression test
4.  Modul C: email template _en/_tr/_es + sender.py patch + 4 test
5.  Modul D: wizard lang picker + 3 test
6.  Modul E: landing i18n routing + 5 vitest
7.  Modul F: validate_install.py + 5 test
8.  Modul G: system_validate MCP + tool count 106→107 + 2 test
9.  Modul H: smart_link skeleton + 4 test
10. Smoke 5 evidence
11. summary + completed/
```

## 6. DoD Checklist

```
[ ] 8 modül A-H tamam
[ ] pytest 367 (342→367, +25 backend)
[ ] vitest 22 (17→22, +5 frontend)
[ ] tool count 107 (system_validate)
[ ] 5 smoke evidence
[ ] backend regression yeşil (010-022)
[ ] Türkçe hard-coded strings sıfır (grep ile doğrula: providers/, patches/, pipelines/, api/ — sadece test ve memory dışı)
[ ] Email templates 24 adet (8 × 3 dil)
[ ] Landing 3 dil routing çalışıyor (npm run dev → /en, /tr, /es)
[ ] summary + completed/
```

## 7. Worker Notları

1. **Locale JSON yapısı flat key dot notation** (`errors.stripe_not_configured`) — nested olmaz (translation tool'lar nested'i sevmez).
2. **EN default zorunlu** — TR/ES eksik anahtar varsa EN'e fallback.
3. **Provider i18n teklifi:** her provider hata mesajı için `t('errors.provider_connection', lang).format(provider=name, exc=str(exc))`.
4. **Email Stripe locale** — `session.customer_details.locale` Stripe checkout'ta var (örn: `tr-TR`); ilk 2 char (`tr`) → preferred_lang. Yoksa `en` default.
5. **Setup wizard step 0** — geri uyumluluk: lang seçimi yapılmamış kurulumlarda `en` default kabul edilir.
6. **Landing i18n** — Next.js 15 app router için `[lang]` dynamic segment + middleware redirect (`/en/`, `/tr/`, `/es/`).
7. **validate_install.py** — `--json` flag default, `--human` flag tablo çıktı opsiyonu.
8. **system_validate cache** — 5dk TTL (önceki cache pattern: `_PRODUCT_CACHE`'de billing_tools.py kullanıldı).
9. **smart_link encryption** — vault sops/age ile (013'te kuruldu) — `vault.encrypt(api_key)`.
10. **Backward compat:** `Accept-Language` header yoksa `en` default; mevcut endpoint'lerin response status_code'ları değişmez (sadece detail mesaj çevrilir).
11. **Locale Türkçe + İspanyolca metinleri** delegation: `ask "translate to Spanish: ..." qwen32b` ve `ask "Türkçe çevir: ..." qwen32b`.
12. **Memory snapshot** task sonu yaz: `session_resume_state_20260427_023.md` (017-022 pattern).
