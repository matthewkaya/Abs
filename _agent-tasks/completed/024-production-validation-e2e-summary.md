# Task 024 — Production Validation + E2E Smoke + Health Hardening — SUMMARY

**Status:** DONE
**Tarih:** 2026-04-27

## Özet

| Metrik | Önce | Sonra | Δ |
|---|---|---|---|
| Backend pytest | 376 + 2 skip | **409 + 2 skip** | **+33** (≥ spec 408) |
| Frontend vitest | 22 | **22** (değişmez) | 0 |
| MCP tool | 107 | **107** (değişmez) | 0 |
| Lighthouse Desktop | 100/93/96/100 | **100/100/100/100** | a11y +7, bp +4 |
| Lighthouse Mobile | 100/93/96/100 | **100/100/100/100** | a11y +7, bp +4 |
| Smoke evidence | — | **8 valid JSON** | — |
| Live API call | — | **0** | — |

## Modüller

### A — MCP Tool Inventory Smoke ✅
- `infra/scripts/mcp_tool_smoke.py` (~270 satır) — 107 tool için minimal call, ok+skip+fail rapor.
- `_SKIP_TOOLS` ~80 entry (live API gerektirenler), `_SAFE_DEFAULTS` ~28 entry no-arg/safe-arg tools.
- Smoke run: **107 = 27 ok + 80 skipped + 0 failed** ✅.
- 5 test (`test_mcp_tool_smoke.py`).

### B — i18n End-to-End ✅
- 3 dil × 3 endpoint (webhook missing-sig + checkout no-key + portal no-key) = 9 live HTTP.
- EN/TR/ES farklı detail mesajları doğrulandı.
- 9 test (`test_i18n_e2e.py`).

### C — Setup Wizard E2E ✅
- Sıralı 6 adım: admin → license → domain → anthropic → providers → test → completed:true.
- + lang picker + out-of-order rejection + idempotency.
- 4 test (`test_setup_wizard_e2e.py`).

### D — Stripe E2E Flow ✅
- Checkout session create (mock) → webhook checkout.session.completed → license + email console fallback.
- Refund webhook → revoked_at set + reason=stripe_refund.
- license_status returns "revoked" with reason.
- 4 test (`test_stripe_e2e_flow.py`).

### E — Smart Link OAuth E2E ✅
- GitHub authorize → state issued → callback validates state.
- Replay (used state) blocked 400.
- API key store for openai/anthropic/cohere/smtp providers.
- Provider list returns 6.
- 4 test (`test_smart_link_e2e.py`).

### F — Lighthouse a11y/bp 100 ✅
- **Root cause a11y 93→100:** FAQ.tsx kullandığı `<dl><dt>...<dd>` deseni `<details>`/`<summary>` ile sarılmıştı — Lighthouse `definition-list` + `dlitem` audit'leri fail. **Fix:** `<ul role="list"><li>` yapıya migrate, `<dt>` yerine `<span role="term">`, `<dd>` yerine `<p>`. Existing `getAllByRole("term")` testi korundu.
- **Root cause bp 96→100:** `errors-in-console: favicon.ico 404`. **Fix:** `app/favicon.ico` (16x16 PNG).
- `next.config.ts` security headers eklendi: X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy, HSTS, CSP (Stripe/Loom allowlist).
- `app/layout.tsx` `lang="tr"` → `lang="en"` (i18n default).
- 2 test (`test_security_headers.py`).
- **Final scores:** desktop+mobile 100/100/100/100.

### G — Docker Compose Smoke ✅
- `infra/scripts/compose_smoke.sh` (~85 satır, executable) — `up -d --build` → wait healthz → `down --remove-orphans`. Output JSON evidence.
- Lightweight CI variant: `docker compose config` validates yaml + service inventory.
- 2 test (`test_compose_smoke.py`): script exists+executable + compose yaml valid.
- Evidence (`06_compose_health.json`): 3 services (backend/caddy/email-cron), 4 volumes, Dockerfile 52 lines + HEALTHCHECK.

### H — Health Endpoint Detaylı ✅
- `app/api/health_full.py` — `GET /v1/health/full` ile 7 dependency check: database, vault, providers (env presence), rag, mcp (107 count), email, data_dir.
- Each check: `{name, ok, detail}`. Overall: `all(c.ok)`.
- `main.py` register `health_full_router`.
- 3 test (`test_health_full.py`).

## Test Breakdown (33 yeni)

| Dosya | Test |
|---|:-:|
| test_mcp_tool_smoke.py | 5 |
| test_i18n_e2e.py | 9 |
| test_setup_wizard_e2e.py | 4 |
| test_stripe_e2e_flow.py | 4 |
| test_smart_link_e2e.py | 4 |
| test_security_headers.py | 2 |
| test_compose_smoke.py | 2 |
| test_health_full.py | 3 |
| **TOPLAM** | **33** |

```
$ .venv/bin/pytest -q --tb=no
409 passed, 2 skipped in 12.42s
$ tool count → 107
$ vitest → 22 passed
```

## Smoke Evidence (`/tmp/abs-024-smoke/evidence/`)

| Dosya | İçerik | Valid |
|---|---|:-:|
| `01_mcp_tool_smoke_report.json` | 107 tool: 27 ok, 80 skip, 0 fail | ✓ |
| `02_i18n_e2e.json` | 3 lang × 3 endpoint live HTTP | ✓ |
| `03_setup_wizard_e2e.json` | 6 step + final completed:true | ✓ |
| `04_stripe_e2e_flow.json` | checkout → create → refund full chain | ✓ |
| `05_smart_link_oauth.json` | providers + GitHub auth+callback + API-key | ✓ |
| `06_compose_health.json` | 3 services + 4 volumes + Dockerfile 52L | ✓ |
| `07_lighthouse_desktop_v2.json` | 100/100/100/100 | ✓ |
| `08_lighthouse_mobile_v2.json` | 100/100/100/100 | ✓ |

## DoD §6 — All Checked

- [x] 8 modül A-H ✅
- [x] pytest **409** (spec floor 408)
- [x] vitest **22** (değişmez, frontend modul yok)
- [x] tool **107** (yeni tool yok, doğrulama task'ı)
- [x] Lighthouse desktop+mobile **100/100/100/100**
- [x] 8 smoke evidence valid JSON
- [x] backend regression yeşil (010-023)
- [x] summary + completed/

## Notable Findings

1. **a11y debt root cause:** `<dl>+<details>+<dt>+<dd>` invalid markup (Lighthouse caught). Tests passing because RTL `getAllByRole("term")` matched both `<dt>` and `<span role="term">` — now `<span role="term">` is canonical.
2. **bp debt root cause:** missing favicon → 404 → console error.
3. **MCP tool 80/107 skipped** çünkü live API gerektiriyor; bu beklenen ve doğru. ok+skip = 107, fail = 0 hedefi tutuldu.
4. **Compose live build** smoke spec'te öneriliyor (5+ dk). Evidence için lightweight `compose config` yöntemi kullanıldı; full live build için `bash infra/scripts/compose_smoke.sh` mevcut (production deploy testi).

## Planlayıcıya Notlar (deferred to 025+)

1. **Compose live up smoke CI** — full image build (5+ dk) GitHub Actions workflow.
2. **MCP live tool tests** — Stripe/OpenAI/Anthropic test ortamı (test API key + cassettes/VCR).
3. **Health full async** — `_check_db` + `_check_rag` parallel asyncio.gather.
4. **Lighthouse mobile fonksiyonel testler** — current `--form-factor=mobile` simüle eder, gerçek device test eksik.
5. **Console error sources** — favicon eklendi, başka 3rd-party widget eklendiğinde tekrar audit gerekli (örn. analytics).
