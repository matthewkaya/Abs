# Task 026 — Smart Link Production (OAuth + Vault + Connect Dashboard)

**Status:** READY (Worker autonomous mode — second of 2-task chain 025→026)
**Tahmini süre:** 4-5 saat
**Bağımlı task'lar:** 023 (smart link skeleton), 013 (vault), 010-025
**Hedef:** 023'teki smart link skeleton'ı **production-grade** seviyeye taşı — gerçek OAuth flow, vault encrypt, dashboard UI, provider validation.

---

## 0. Bağlam

023'te `app/api/smart_link.py` skeleton + 4 endpoint kuruldu (mock OAuth). Şimdi:
- GitHub OAuth gerçek flow (state + code → token exchange + refresh logic)
- Slack OAuth (channel post için)
- API key vault encrypt (013 sops/age pattern)
- Provider key validation (test API call + isolate failure)
- Connect dashboard UI (`core/landing` veya `app/static`)
- Connected services sayfası

---

## 1. Amaç (DoD)

- [ ] GitHub OAuth gerçek state + code exchange + token refresh
- [ ] Slack OAuth + minimal channel post
- [ ] API key encrypt → vault (sops + age)
- [ ] API key rotation endpoint
- [ ] Provider validate (OpenAI/Anthropic/Cohere key live test, isolate)
- [ ] Connect dashboard UI (vanilla `app/static/connect.html` + `core/landing/app/connect/`)
- [ ] Connected services list endpoint (DB query + decrypt)
- [ ] 25+ yeni test, pytest 429 → ~454
- [ ] Tool count 108 → 110 (`smart_link_status`, `provider_validate`)
- [ ] 5 smoke evidence

---

## 2. Modüller

### Modul A — GitHub OAuth Production
**Patch:** `app/api/smart_link.py`
- `GET /v1/smart-link/github/authorize` — state generate (CSRF token, 10dk TTL DB cache) + redirect URL
- `GET /v1/smart-link/github/callback?code=&state=` — state verify, code → token POST `https://github.com/login/oauth/access_token`, scope check, encrypt + DB store
- `POST /v1/smart-link/github/refresh` — refresh token rotation
- `DELETE /v1/smart-link/github` — revoke + DB clear
- 5 test (mock httpx oauth flow, state replay protection, scope validation, refresh, revoke)

### Modul B — Slack OAuth + Webhook Post
**Yeni:** `app/api/integrations/slack.py`
- `GET /v1/smart-link/slack/authorize` — Slack OAuth start
- `GET /v1/smart-link/slack/callback` — token exchange + bot token store (vault encrypted)
- `POST /v1/smart-link/slack/post` — `{channel, text}` minimal channel post
- 4 test

### Modul C — API Key Vault Encrypt
**Yeni:** `app/smart_link/vault_secrets.py` (~120 satır)
- `encrypt_secret(key_name, value)` — sops/age (013 pattern), DB'ye encrypted_value yaz
- `decrypt_secret(key_name)` — vault decrypt + cache 5dk
- `rotate_secret(key_name, new_value)` — eski sil, yeni encrypt + DB update + audit log
- DB model: `ConnectedSecret` (key_name, provider, encrypted_value, created_at, last_validated_at)
- 5 test (encrypt roundtrip, rotation audit, cache expire)

### Modul D — Provider Validation
**Yeni:** `app/smart_link/provider_validators.py`
- `validate_openai(key)` — `GET https://api.openai.com/v1/models` + `Authorization: Bearer`
- `validate_anthropic(key)` — `POST https://api.anthropic.com/v1/messages` minimal probe
- `validate_cohere(key)` — `GET https://api.cohere.ai/v1/models`
- `validate_groq(key)` — `GET https://api.groq.com/openai/v1/models`
- `validate_gemini(key)` — `GET https://generativelanguage.googleapis.com/v1beta/models?key=...`
- Output: `{ok: bool, latency_ms: int, error: str|null}`
- Live çağrı YOK testte — `monkeypatch httpx`
- 5 test

### Modul E — POST /v1/smart-link/api-key Production
**Patch:** `app/api/smart_link.py::api_key_endpoint`
- Body: `{provider, api_key}` validation
- Provider-specific validate (Modul D çağır)
- Geçerli ise vault encrypt + DB store
- 422 if invalid key (not just stored)
- 4 test

### Modul F — Connected Services Dashboard
**Yeni HTML:** `app/static/connect.html` — vanilla, `/v1/smart-link/connected-services` poll
- Provider kartları (GitHub, Slack, OpenAI, Anthropic, Cohere, Groq, Gemini)
- Her kart: bağlı mı, last_validated_at, refresh/revoke butonu
- Tema: Automatia premium (mavi)
- **NEW:** `GET /v1/smart-link/connected-services` — DB query + son validation status
- **NEW:** `core/landing/app/connect/page.tsx` — public-facing equivalent
- 4 test

### Modul G — MCP Tools
**Yeni:** `app/mcp/tools/smart_link_tools.py`
- `smart_link_status()` — bağlı servis listesi + son validation
- `provider_validate(provider, api_key)` — Modul D wrapper
- 3 test
- Tool count 108 → **110**

---

## 3. Test Stratejisi (25 test)

| Modül | Test |
|---|:-:|
| A GitHub OAuth | 5 |
| B Slack OAuth | 4 |
| C vault secrets | 5 |
| D provider validators | 5 |
| E api-key prod | 4 |
| F dashboard | 4 |
| G MCP tools | 3 |
| Tool count guard | (1 update) |
| **TOPLAM** | **30** |

Backend: 429 → **459** (+30). Tool: 108 → **110**. Frontend: 22 → 27 (+5 vitest connect page).

---

## 4. Smoke Evidence (`/tmp/abs-026-smoke/evidence/`)

1. `01_github_oauth_flow.json` — mock authorize + callback + token store
2. `02_vault_encrypt_roundtrip.json` — encrypt → DB → decrypt eşleşme
3. `03_provider_validators.json` — 5 provider mock validation
4. `04_connect_dashboard_render.json` — `/v1/smart-link/connected-services` response
5. `05_smart_link_status_mcp.json` — MCP tool response

---

## 5. Adım Adım

```
1. baseline (025 sonu) pytest 429 + tool 108
2. Modul A: GitHub OAuth + 5 test
3. Modul B: Slack OAuth + 4 test
4. Modul C: vault_secrets + 5 test
5. Modul D: provider_validators + 5 test
6. Modul E: api-key prod + 4 test
7. Modul F: connect dashboard + 4 test
8. Modul G: MCP tools + tool 108→110 + 3 test
9. Smoke 5 evidence
10. summary + completed/
11. Memory snapshot session_resume_state_20260427_026.md
```

## 6. DoD Checklist

```
[ ] 7 modül A-G tamam
[ ] pytest 459 (+30 from 025 baseline 429)
[ ] vitest 27 (+5 connect page)
[ ] tool 110
[ ] 5 smoke evidence
[ ] regression sıfır (010-025)
[ ] summary + completed/
[ ] memory snapshot 026
```

## 7. Worker Notları

1. **Live OAuth API'ye DOKUNMA** — tüm test mock (httpx monkeypatch). Smoke evidence mock data ile.
2. GitHub OAuth dummy client_id: `ABS_GITHUB_CLIENT_ID`/`ABS_GITHUB_CLIENT_SECRET` env, vault'tan oku.
3. State CSRF token: `secrets.token_urlsafe(32)`, DB cache `OAuthState` table 10dk TTL.
4. Vault encrypt 013 pattern (`app/vault/runner.py` zaten var). `ConnectedSecret.encrypted_value` BLOB veya base64 string.
5. Provider validate timeout 5s; fail edenler `ok: false` + error string.
6. Connect dashboard polling 60s (state nadiren değişir).
7. `GET /v1/smart-link/connected-services` Bearer auth (admin token, 022 demo_admin pattern).
8. Slack OAuth scope: `chat:write`, `channels:read`. Bot token store, user token saklamayız.
9. **026 BİTİNCE:** /tmp/abs-autonomous-success-025-026.md final rapor (chain özet).
