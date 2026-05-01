# Task 028 — Webhook + OAuth Security Hardening

**Status:** READY (Worker autonomous mode — second of 3-task chain 027→028→029)
**Tahmini süre:** 4-5 saat

## ⚠️ DELEGATION ZORUNLU — 5H CONTEXT LIMIT ALARMI

Önceki task 027'de delegation %4 ölçüldü (hedef %15+). 5 saatlik Claude context sınırına yaklaşıyoruz. Bu task'ta her 200+ kelimelik doc için **ZORUNLU `ask "..." qwen32b/gptoss`** kullan, kendi yazma:

- Modul F **webhook-rotation-runbook.md (~800w)** → `ask "Stripe Slack GitHub webhook secret rotation runbook EN ~800 words sections compromise scenario..." gptoss`
- Modul A-G testlerindeki long prompt mock'ları → `ask "..." kimi`
- Validator/parser test fixture'ları → `ask "..." kimi`

Çıktıyı al → Write tool ile dosyaya kaydet. Self-write etme.
**Bağımlı task'lar:** 011 (Stripe webhook), 017 (webhook idempotency), 026 (smart link OAuth), 027 (vault hardening)
**Hedef:** 026'da skeleton kurulan OAuth flow'ları + Stripe webhook'ları **gerçek production-grade hardening** seviyesine çıkar — Slack signing verify, GitHub App migration foundation, OAuth refresh token gerçek flow, idempotent reflexion (event replay), webhook secret rotation runbook.

---

## 0. Bağlam

026 deferred edilen 4 madde:
1. **Vault sops production** (027'de)
2. **GitHub App migration** — şu an OAuth, ileride GitHub App + permissions ⚠️ 028'de
3. **Slack signing verify** — webhook signature doğrulama eksik ⚠️ 028'de
4. **Refresh token real flow** — şu an store ediyor ama actual refresh çağrısı mock ⚠️ 028'de

Ek hardening:
- **Stripe webhook event replay protection** — 017'de event_id idempotent ama 24h+ replay testi yok
- **OAuth state CSRF token TTL** — şu an 10dk cache, distributed env'de race condition test edilmedi
- **Webhook secret rotation prosedürü** — runbook eksik (013 manifest key rotate var ama webhook yok)
- **Rate limiting** — `/v1/billing/portal`, `/v1/smart-link/*` brute force koruması yok

---

## 1. Amaç (DoD)

- [ ] **Slack webhook signing verify** — `X-Slack-Signature` HMAC SHA256 doğrulama (replay attack guard)
- [ ] **GitHub App migration foundation** — App manifest YAML + private key handling + installation flow (skeleton, prod migration sonra)
- [ ] **OAuth refresh token gerçek flow** — token expiry detect → POST refresh endpoint → DB update
- [ ] **Webhook event replay protection (24h+)** — `WebhookEvent.received_at` index + 7 gün retention
- [ ] **OAuth state TTL** — `OAuthState` table 10dk TTL + cleanup cron
- [ ] **Webhook secret rotation runbook** — Stripe + Slack için ayrı (`docs/webhook-rotation-runbook.md`)
- [ ] **Rate limiting middleware** — slowapi entegrasyonu, kritik endpoint'lerde
- [ ] 35+ yeni test, pytest 491 → ~528
- [ ] Tool count 111 → 112 (`security_audit`)
- [ ] 6 smoke evidence

---

## 2. Modüller

### Modul A — Slack Webhook Signing Verify
**Patch:** `app/api/integrations/slack.py`
- `verify_slack_signature(signing_secret, timestamp, body, signature) -> bool`:
  - Format: `sig = "v0=" + HMAC-SHA256(signing_secret, "v0:" + timestamp + ":" + body)`
  - Timestamp 5dk içinde mi (replay attack guard)
  - constant-time compare (`hmac.compare_digest`)
- `POST /v1/integrations/slack/webhook` — events_api callback
  - Signature verify → fail = 401
  - URL verification challenge (event.type == "url_verification")
  - Event handle: app_mention, message
- 6 test (signature pass/fail, timestamp expired, replay attack, URL verification, malformed body, constant-time timing leak)

### Modul B — GitHub App Migration Foundation
**Yeni:** `app/api/integrations/github_app.py` (~200 satır)
- `app/integrations/github_app_manifest.yml` — GitHub App manifest (permissions, webhook URL, events)
- `generate_app_jwt(app_id, private_key)` — RS256 JWT (10dk TTL)
- `installation_token(app_id, installation_id, private_key)` — installation-specific token
- `webhook_handler` — events: installation, push, pull_request (skeleton)
- Mevcut OAuth flow'a parallel (deprecate değil, opt-in migration)
- 5 test (JWT generate, installation token, webhook signature, manifest validate, OAuth-vs-App routing)

### Modul C — OAuth Refresh Token Gerçek Flow
**Patch:** `app/api/smart_link.py`
- `_token_expired(connected_secret) -> bool` — DB'den expires_at kontrol
- `refresh_github_token(connected_secret)` — GitHub refresh token endpoint çağrı
- Background task: 30dk'da bir expiry check, 1 saat öncesi refresh
- Vault encrypt yeni token + audit log (`action: "token_refresh"`)
- 6 test (expired detection, successful refresh, refresh fail → revoke, race condition, audit entry)

### Modul D — Webhook Event Replay Protection
**Patch:** `app/api/webhooks/stripe.py` + `app/api/webhooks/idempotency.py`
- `WebhookEvent.received_at` üzerinde index (mevcut, doğrula)
- **7 gün retention** (017'de purge cron 90 gün — ama replay protection için 7 gün yeterli, küçült)
- **24h+ retention test:** event_id 7 gün önce, aynı id şimdi gelirse `replay_protected` flag
- `infra/scripts/purge_webhook_events.py` 7 gün param ekle
- 4 test (24h replay, 7 gün replay, retention boundary, idempotency under load)

### Modul E — OAuth State TTL Cleanup
**Yeni:** `infra/scripts/oauth_state_cleanup.py`
- `OAuthState` table query (mevcut state.created_at)
- 10dk üzeri olanları sil
- `infra/cron/oauth_state_cleanup.cron` her 5dk
- Race condition: state pop atomic (state used → mark + don't reuse)
- 4 test (TTL expire, atomic pop, race, retention)

### Modul F — Webhook Secret Rotation Runbook
**Yeni:** `docs/webhook-rotation-runbook.md` (~800 kelime EN)
- Stripe webhook secret rotation:
  - Stripe Dashboard → Webhooks → Roll secret → vault update → backend restart
  - Verify: send test webhook from Dashboard
- Slack signing secret:
  - Slack App settings → regenerate → vault update → restart
- GitHub App webhook secret:
  - GitHub App settings → re-create → vault update → restart
- Compromise scenario (acil rotation, audit log inceleme, customer notify)
- 1 test (markdown sections + min 600 kelime)

### Modul G — Rate Limiting Middleware
**Yeni:** `app/middleware/rate_limit.py`
- slowapi (Redis backend opsiyonel, in-memory default)
- `@limiter.limit("10/minute")` decorator
- Kritik endpoint'ler:
  - `POST /v1/checkout/create-session` — 10/min/IP
  - `POST /v1/billing/portal` — 5/min/IP
  - `POST /v1/smart-link/api-key` — 5/min/IP
  - `GET /v1/smart-link/github/authorize` — 10/min/IP
- 429 response standard format
- 6 test (limit hit, reset window, multiple IPs, concurrent, header check)

### Modul H — `security_audit` MCP Tool
**Yeni:** `app/mcp/tools/security_tools.py`
- `security_audit()` output:
  ```python
  {
    "webhook_secrets": {"stripe_set": bool, "slack_set": bool, "last_rotated_days_ago": int},
    "oauth_active_states": int,  # son 10dk içinde active CSRF tokens
    "rate_limit_breaches_24h": int,  # 429 sayım
    "vault_audit": vault_audit_status_inline(),
    "tls_cert_expires_days": int,  # Caddy cert kontrolü
    "overall_score": "ok" | "warn" | "danger"
  }
  ```
- 3 test
- Tool count 111 → **112**

---

## 3. Test Stratejisi (35+ test)

| Modül | Test |
|---|:-:|
| A Slack signing | 6 |
| B GitHub App | 5 |
| C OAuth refresh | 6 |
| D replay protection | 4 |
| E OAuth state cleanup | 4 |
| F rotation runbook | 1 |
| G rate limiting | 6 |
| H security_audit MCP | 3 |
| Tool count guard | (1 update) |
| **TOPLAM** | **35** |

Backend: 491 → **526** (+35). Frontend: 27 (değişmez).

---

## 4. Smoke Evidence (`/tmp/abs-028-smoke/evidence/`)

1. `01_slack_signature_verify.json` — pass/fail/replay/url_verification 4 senaryo
2. `02_github_app_jwt.json` — JWT generate + installation token
3. `03_oauth_refresh_flow.json` — expired → refresh → vault update + audit
4. `04_replay_protection_24h.json` — duplicate event 7 gün sonra ignored
5. `05_rate_limit_429.json` — 11. çağrı 429 + reset
6. `06_security_audit_mcp.json` — MCP tool response

---

## 5. Adım Adım

```
1. baseline pytest 491 + tool 111
2. Modul A: Slack signing + 6 test
3. Modul B: GitHub App foundation + 5 test
4. Modul C: OAuth refresh + 6 test
5. Modul D: replay protection + 4 test
6. Modul E: OAuth state cleanup + 4 test
7. Modul F: rotation runbook + 1 test
8. Modul G: rate limiting + 6 test
9. Modul H: security_audit MCP + count 111→112 + 3 test
10. Smoke 6 evidence
11. summary + completed/
12. memory snapshot 028
```

## 6. DoD Checklist

```
[ ] 8 modül A-H tamam
[ ] pytest 526 (+35 from 491 baseline)
[ ] tool 112
[ ] 6 smoke evidence
[ ] regression sıfır (010-027)
[ ] Slack signature constant-time compare ispatlandı
[ ] GitHub App JWT RS256 doğru imzalanmış
[ ] OAuth refresh atomic (vault update)
[ ] Replay protection 7 gün boundary
[ ] Rate limit 429 + Retry-After header
[ ] summary + completed/
[ ] memory snapshot 028
```

## 7. Worker Notları

1. **Slack signing secret** — env: `ABS_SLACK_SIGNING_SECRET`. Test'te dummy `8f742231b10e8888abcd99b1ee...` (64 char hex).
2. **GitHub App private key** — RSA 4096, vault encrypted. Test'te `cryptography.hazmat.primitives.asymmetric.rsa.generate_private_key`.
3. **OAuth refresh** — GitHub OAuth Apps refresh token TTL 6 ay; gerçek refresh endpoint `POST https://github.com/login/oauth/access_token` mock'lanır.
4. **Replay protection** — `WebhookEvent.received_at < now - 7 days` → silent ignore (audit log entry); 7 gün içinde duplicate → 200 + `duplicate: true`.
5. **OAuth state atomic pop** — DB transaction with `SELECT ... FOR UPDATE` (SQLite WAL mode'da SELECT lock yetersiz; SQLite için `BEGIN IMMEDIATE`). Production PostgreSQL'de `FOR UPDATE`.
6. **Rate limit storage** — slowapi default in-memory; multi-instance deployment için Redis önerisi runbook'ta.
7. **Webhook rotation runbook** — Stripe/Slack/GitHub için ayrı bölümler. Compromise scenario'da incident response checklist (notify customer, audit, rotate).
8. **Security audit MCP** — admin Bearer token gerek; rastgele kullanıcı erişemez.
9. **slowapi dependency** — `pip install slowapi` (Pyright extension). Yoksa middleware no-op (graceful degrade).
10. **Backward compat:** mevcut Stripe webhook (011), checkout (011), smart_link (026) endpoint'leri davranışı değişmez. Sadece security layer eklenir.
11. **Memory snapshot:** task sonu `session_resume_state_20260427_028.md`.
