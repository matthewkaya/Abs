# Task 032 — Admin Dashboard + Telemetry Foundation

**Status:** READY (Worker autonomous mode — third of 3-task chain 030→031→032)
**Tahmini süre:** 4-5 saat
**Bağımlı task'lar:** 022 (wizard funnel), 025 (status page), 028 (security_audit), 029 (compliance), 031 (beta metrics)

## ⚠️ DELEGATION ZORUNLU
- Admin guide doc (~800w EN) → `ask "..." gptoss`
- Telemetry primer (~600w) → `ask "..." gptoss`
- Hook BLOCK aktif

## 0. Bağlam

Solo operatör için **tek panoraması** yok şu an. Mevcut durumu görmek için 5+ farklı endpoint çağırması gerek (status, billing, security, compliance, beta metrics). Bu task hepsini **tek admin dashboard**'da birleştirir.

Müşteri-facing değil — **sadece Enes erişir**, JWT admin token + audit log.

Worker 030+031 sonrası 120 tool, 604 backend test. 032 admin layer — operasyonel rahatlık.

---

## 1. Amaç (DoD)

- [ ] **Admin auth** — JWT admin token (separate from license JWT), 24h TTL, MFA-style (Bearer + IP whitelist opt-in)
- [ ] **Admin dashboard endpoint** — `GET /v1/admin/dashboard` aggregated data
- [ ] **Real-time metrics** — 5min refresh, license/revenue/churn/error/security stats
- [ ] **Admin web UI** — `app/static/admin/index.html` (vanilla JS, brand-aligned)
- [ ] **License analytics** — `GET /v1/admin/analytics/licenses` (cohort, retention, expiry calendar)
- [ ] **Churn detection** — `GET /v1/admin/analytics/churn` (kullanım azalan müşteri tespit)
- [ ] **Error monitor** — `GET /v1/admin/errors/recent` (son 100 webhook fail, MCP tool fail)
- [ ] **Audit log viewer** — `GET /v1/admin/audit/recent` (vault + customer audit birleşik)
- [ ] **Admin guide doc** — `docs/operations/admin-guide.md` (~800w EN, delegate gptoss)
- [ ] **Telemetry primer** — `docs/operations/telemetry.md` (~600w, hangi metric ne demek)
- [ ] **MCP tool:** `admin_overview` — kapsamlı snapshot
- [ ] 30+ yeni test, pytest 604 → ~635
- [ ] vitest 36 → 39 (admin UI tests)
- [ ] Tool count 120 → 121
- [ ] 6 smoke evidence

---

## 2. Modüller

### Modul A — Admin Auth (JWT + IP)
**Yeni:** `app/api/admin/auth.py`
- `POST /v1/admin/login` body: `{password}` (bcrypt hash compare, env `ABS_ADMIN_PASSWORD_HASH`)
- Returns: JWT 24h + `Set-Cookie: abs_admin=...; HttpOnly; Secure; SameSite=Strict`
- Optional IP whitelist (env `ABS_ADMIN_IP_WHITELIST`, comma-separated)
- Rate limit 5 attempts/15min (slowapi 028)
- 5 test (login success, wrong password, IP block, rate limit, JWT verify)

### Modul B — Aggregated Dashboard Endpoint
**Yeni:** `app/api/admin/dashboard.py`
- `GET /v1/admin/dashboard` — JWT admin
- Aggregates 5 sources:
  - billing_status (017): revenue today/MTD/total, license counts
  - security_audit (028): webhook secrets, oauth states, rate limit breaches
  - compliance_status (029): GDPR/SOC2 readiness
  - beta_metrics (031): waitlist, conversion
  - vault_audit_status (027): chain integrity, recent rotations
- Cache 5min (`/tmp/abs_admin_dashboard_cache.json`)
- 6 test (auth, aggregation shape, cache hit, cache invalidation, partial failure, performance <200ms)

### Modul C — Real-time Metrics + Web UI
**Yeni:** `app/static/admin/index.html`
- Vanilla JS, brand colors (Automatia mavi)
- 6 widget:
  1. Revenue (today / MTD / total)
  2. Licenses (active / expired / revoked)
  3. Security score (webhook secrets, rate limit, vault chain)
  4. Compliance (GDPR/SOC2 progress bar)
  5. Beta funnel (signups → approved → paid)
  6. Recent errors (10 most recent)
- 30s auto-refresh (fetch dashboard endpoint)
- Responsive (mobile-friendly)

3 vitest (`__tests__/AdminDashboard.test.tsx` if frontend Next.js, or Playwright snapshot for vanilla):
- widget render
- auth redirect
- error handling

### Modul D — License Analytics
**Yeni:** `app/api/admin/analytics_licenses.py`
- `GET /v1/admin/analytics/licenses?cohort=monthly`
- Cohort retention table: signup month vs active months
- Expiry calendar: next 90 days expiry distribution
- Tier breakdown: self-host / team-5 / team-10 percent
- 5 test

### Modul E — Churn Detection
**Yeni:** `app/api/admin/churn.py`
- `GET /v1/admin/analytics/churn` — son 30 gün kullanım azalan license_jti listesi
- Heuristic: feature_usage trend < 50% of 7d-avg → flag
- Alert: Discord webhook
- 4 test

### Modul F — Error Monitor
**Yeni:** `app/api/admin/errors_recent.py`
- `GET /v1/admin/errors/recent?limit=100` — 4 kaynak birleşik:
  - WebhookEvent.error NOT NULL
  - MCP tool error (logger fail counter)
  - Vault decrypt fail
  - SMTP send fail
- Pagination + severity filter
- 4 test

### Modul G — Audit Log Viewer
**Yeni:** `app/api/admin/audit_recent.py`
- `GET /v1/admin/audit/recent?limit=200&source=vault|customer|webhook`
- Birleşik VaultAuditEntry (027) + CustomerAuditEntry (029) + WebhookEvent (017)
- 4 test

### Modul H — Admin Guide + Telemetry Primer
**Yeni:** `docs/operations/admin-guide.md` (~800w EN, delegate gptoss):
- Login + IP whitelist setup
- Dashboard widgets açıklama
- Daily/weekly operational checklist
- Common tasks (revoke license, refund, beta approve)

**Yeni:** `docs/operations/telemetry.md` (~600w EN, gptoss):
- Each metric definition (revenue gross vs net, churn formula, retention cohort, security score)
- How metrics computed
- When to alert

2 test (`test_admin_docs.py`): docs exist + min word count + sections.

### Modul I — `admin_overview` MCP Tool
**Yeni:** `app/mcp/tools/admin_tools.py`
- `admin_overview()` — dashboard endpoint'in MCP wrapper'ı (Bearer admin token gerek)
- 2 test
- Tool count 120 → **121**

---

## 3. Test Stratejisi (30+ test)

| Modül | Test |
|---|:-:|
| A admin auth | 5 |
| B dashboard aggregated | 6 |
| C web UI (frontend) | 3 vitest |
| D license analytics | 5 |
| E churn detection | 4 |
| F error monitor | 4 |
| G audit viewer | 4 |
| H docs | 2 |
| I admin_overview MCP | 2 |
| Tool count guard | 1 update |
| **TOPLAM** | **33 backend + 3 frontend = 36** |

Backend: 604 → **637**. Frontend: 36 → **39**. Tool: 120 → **121**.

---

## 4. Smoke Evidence (`/tmp/abs-032-smoke/evidence/`)

1. `01_admin_login_flow.json` — login + JWT + IP check
2. `02_dashboard_aggregated.json` — 5-source response
3. `03_web_ui_render.png` — admin/index.html screenshot
4. `04_license_analytics.json` — cohort retention table
5. `05_churn_detection.json` — flagged licenses + reason
6. `06_admin_overview_mcp.json` — MCP tool response

---

## 5. Adım Adım

```
1. baseline pytest 604 + tool 120
2. Modul A: admin auth + 5 test
3. Modul B: dashboard endpoint + cache + 6 test
4. Modul C: web UI HTML + 3 vitest
5. Modul D: license analytics + 5 test
6. Modul E: churn detection + Discord alert + 4 test
7. Modul F: error monitor + 4 test
8. Modul G: audit viewer + 4 test
9. Modul H: admin guide + telemetry primer (gptoss EN ~1400w toplam) + 2 test
10. Modul I: admin_overview MCP + count 120→121 + 2 test
11. 6 smoke evidence
12. summary + completed/
13. memory snapshot 032
14. /tmp/abs-autonomous-success-030-032.md final chain raporu
```

## 6. DoD

```
[ ] 9 modül A-I tamam
[ ] pytest 637 (+33)
[ ] vitest 39 (+3)
[ ] tool 121 (+1)
[ ] 6 smoke evidence
[ ] regression sıfır
[ ] summary + completed/
[ ] memory snapshot 032
[ ] chain final report
```

## 7. Notlar

1. **Admin password** — bcrypt hash (passlib), `ABS_ADMIN_PASSWORD_HASH` env. Plain password ASLA log/store.
2. **JWT admin secret** — separate from license JWT (`ABS_ADMIN_JWT_SECRET`). Vault'a yaz (013).
3. **IP whitelist optional** — env yoksa whitelist disabled (sadece bcrypt). Production'da set zorunlu (runbook'ta not).
4. **Dashboard cache** — 5min TTL yeterli; canlı revenue trend için 1min override edilebilir.
5. **Web UI vanilla JS** — Next.js bağımlılığı YOK; Caddy serve eder static path.
6. **Churn alert eşik** — 7d-avg < 50% → flag. Eşik kaldırılabilir env (`ABS_CHURN_THRESHOLD=0.5`).
7. **Memory snapshot:** task sonu + chain final raporu.
