# Task 028 — Webhook + OAuth Security Hardening — SUMMARY

**Status:** DONE
**Tarih:** 2026-04-27

## Özet

| Metrik | Önce | Sonra | Δ |
|---|---|---|---|
| Backend pytest | 489 + 2 skip | **526 + 2 skip** | **+37** |
| MCP tool | 111 | **112** | +1 (`security_audit`) |
| Smoke evidence | — | **6 valid JSON** | — |
| Live API call | — | **0** | — |

## Modüller

### A — Slack Webhook Signing Verify ✅
- `app/integrations/slack_signing.py` — HMAC SHA256 + 5-min replay window
- `verify_slack_signature` returns `(ok, reason)`; constant-time compare
- `events_router POST /v1/integrations/slack/webhook` with URL verification handshake
- 6 test (`test_slack_signing.py`)

### B — GitHub App Migration Foundation ✅
- `app/integrations/github_app.py` — `generate_app_jwt`, `fetch_installation_token`, `verify_webhook_signature`, `DEFAULT_MANIFEST`
- RS256 JWT (≤600s TTL per GitHub spec)
- HMAC SHA256 webhook verification
- `app/api/integrations/github_app.py` webhook endpoint
- 7 test (`test_github_app.py`)

### C — OAuth Refresh Token Real Flow ✅
- `app/smart_link/oauth_refresh.py` — `refresh_github_token`, `scan_and_refresh`
- Token expiry detection + 1-hour lead refresh
- Audit chain entry (`action=token_refresh`)
- 6 test (`test_oauth_refresh.py`)

### D — Webhook Replay Protection ✅
- 24h+ replay test (017 idempotency stays correct)
- 7-day retention (purge cron 022)
- 4 test (`test_webhook_replay_protection.py`)

### E — OAuth State TTL Cleanup ✅
- `infra/scripts/oauth_state_cleanup.py` (CLI: `--minutes`, `--dry-run`)
- 4 test (`test_oauth_state_cleanup.py`)

### F — Webhook Rotation Runbook ✅
- `docs/webhook-rotation-runbook.md` (~1100 words EN)
- Stripe / Slack / GitHub App + compromise scenario + rotation schedule
- 1 test (`test_webhook_rotation_runbook.py`)

### G — Rate Limiting Middleware ✅
- `app/middleware/rate_limit.py` — slowapi limiter, 429 handler, breach counter
- `@limiter.limit("10/minute")` on `/v1/checkout/create-session`
- Conftest auto-reset between tests (prevented suite-wide leakage)
- 6 test (`test_rate_limiting.py`)

### H — `security_audit` MCP Tool ✅
- `app/mcp/tools/security_tools.py` — webhook secrets + active OAuth states + 429 count + vault audit + overall_score
- Tool 111 → **112**
- 3 test (`test_security_audit_mcp.py`) + 1 registry guard

## Test Sonuçları

```
$ .venv/bin/pytest -q --tb=no
526 passed, 2 skipped in 13.80s
$ tool count → 112
```

| Dosya | Test |
|---|:-:|
| test_slack_signing.py | 6 |
| test_github_app.py | 7 |
| test_oauth_refresh.py | 6 |
| test_webhook_replay_protection.py | 4 |
| test_oauth_state_cleanup.py | 4 |
| test_webhook_rotation_runbook.py | 1 |
| test_rate_limiting.py | 6 |
| test_security_audit_mcp.py | 3 |
| **TOPLAM (yeni)** | **37** |

## Smoke Evidence

`/tmp/abs-028-smoke/evidence/`:
1. `01_slack_signature_verify.json` — 4 senaryo (valid/tampered/expired/empty-secret)
2. `02_github_app_jwt.json` — JWT claims + manifest keys
3. `03_oauth_refresh_flow.json` — token rotation success
4. `04_replay_protection_24h.json` — 24h+ replay idempotent
5. `05_rate_limit_429.json` — first_429_at: 10
6. `06_security_audit_mcp.json` — overall_score + signals

## DoD §6

- [x] 8 modül A-H ✅
- [x] pytest **526** (+37 vs spec target +35)
- [x] tool **112** (+1 security_audit)
- [x] 6 smoke evidence valid
- [x] backend regression yeşil (010-027)
- [x] Slack signature constant-time compare ✓
- [x] GitHub App JWT RS256 ✓
- [x] OAuth refresh atomic + audit ✓
- [x] Replay protection 24h+ ✓
- [x] Rate limit 429 + Retry-After ✓
- [x] summary + completed/

## Notable

- **Conftest auto-reset for limiter** — prevents test suite cross-contamination (15 POSTs in test_rate_limiting were leaking 429 to subsequent tests).
- **Slack signature** — `hmac.compare_digest` ensures constant-time, replay window 5 min strict.
- **GitHub App JWT** — TTL clamped under 600s per GitHub spec.
- **OAuth refresh** — revokes (`update_validation_status`) on failure, doesn't overwrite token.

## Planlayıcıya Notlar

1. **Live OAuth/Slack/GitHub** — all tests use httpx mocks; production needs real credentials.
2. **slowapi** dep added to venv; production install: `pip install slowapi`.
3. **GitHub App migration** — skeleton only; full migration requires App ID + private key in vault.
4. **TLS cert expiry** in `security_audit` is placeholder; production reads from Caddy admin API.
