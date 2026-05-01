# Task 031 — Beta Launch Prep (Lisans + Onboarding + Outreach + Status)

**Status:** READY (Worker autonomous mode — second of 3-task chain 030→031→032)
**Tahmini süre:** 3-4 saat
**Bağımlı task'lar:** 011 (Stripe), 019 (email), 025 (beta lisans gen + status page), 029 (consent), 030 (provider catalog)

## ⚠️ DELEGATION ZORUNLU
- Welcome/onboarding email content (~600w EN+TR+ES) → `ask "..." qwen32b`
- Outreach template (LinkedIn/Twitter/HN) → `ask "..." gptoss`
- Hook 5000+ char BLOCK aktif — uzun docs için zorunlu

## 0. Bağlam

025'te beta lisans generator + status page kuruldu. AMA:
- Beta lisans **manuel CLI** ile veriliyor (`generate_beta_license.py`) — otomasyon yok
- Welcome email zincirleme yok (sadece tek `license_delivery.html`)
- Outreach template'leri yok
- Discord webhook integration var ama beta lisans event flow eksik
- Status page basit, real-time license counter yok

Toplantı yaklaşıyor → ürünü **gerçekten ilk müşteriye satabilir** seviyeye çıkar.

---

## 1. Amaç (DoD)

- [ ] **Beta lisans portal** — `POST /v1/beta/request` (email + use case + auto-approve veya manual queue)
- [ ] **Welcome email sequence** — 5-email serisi (immediate, 24h, 3d, 7d, 14d) trigger by license JTI
- [ ] **Outreach templates** — `docs/marketing/outreach-templates.md` (LinkedIn DM, Twitter thread, HN Show, email cold)
- [ ] **Status page real-time enhanced** — license_count, mrr_estimate, recent_activity (auth-protected admin)
- [ ] **Discord beta event flow** — license_requested → admin notify → approved → customer notify
- [ ] **Beta lisans queue + admin endpoint** — `GET /v1/admin/beta/queue`, `POST /v1/admin/beta/{id}/approve`
- [ ] **Public landing CTA** — "Request Beta Access" button (Bilgi formu + Stripe checkout opsiyon paralel)
- [ ] **MCP tool:** `beta_metrics` (waitlist count, conversion rate, recent signups)
- [ ] 25+ yeni test, pytest 577 → ~602
- [ ] vitest 33 → 36 (beta request form tests)
- [ ] Tool count 119 → 120
- [ ] 6 smoke evidence

---

## 2. Modüller

### Modul A — Beta Request Endpoint + Queue
**Yeni:** `app/api/beta_portal.py`
- `POST /v1/beta/request` body: `{email, name, company, use_case, lang: "en"|"tr"|"es"}`
- `BetaRequest` SQLModel: id, email, name, company, use_case, lang, status (pending|approved|rejected), created_at, approved_at, license_jti
- Rate limit: 1 request/email/day
- Anti-spam: simple captcha-less honeypot field
- Auto-approve mode (env `ABS_BETA_AUTO_APPROVE=true`) → license generate + email
- Manual mode → queue + Discord notify
- 5 test (request, dupe, anti-spam, auto-approve, manual queue)

### Modul B — Welcome Email Sequence (5 email)
**Yeni templates** (`app/email/templates/beta_*_{en,tr,es}.html`):
1. `beta_welcome_*.html` (immediate) — license + setup quick guide
2. `beta_walkthrough_*.html` (24h) — first MCP tool call rehber
3. `beta_first_success_*.html` (3d) — kullanım stat + feature highlight
4. `beta_check_in_*.html` (7d) — feedback request, NPS link
5. `beta_renewal_offer_*.html` (14d) — paid plan CTA + 50% discount code

**Scheduler:** `app/email/beta_sequence.py`:
- License generated → schedule 5 email (DB row per scheduled email)
- Background task `infra/scripts/email_sequence_tick.py` (every 1h)
- Idempotent: aynı license + step duplicate atlar

15 dosya × 3 dil = 45 dosya — toplam ~3000w EN ana + qwen32b ile TR/ES çevir.

8 test: schedule create, tick send, idempotent, 5 step lifecycle, NPS link generate, anti-overlap.

### Modul C — Outreach Templates Doc
**Yeni:** `docs/marketing/outreach-templates.md` (~1200w EN, delegate gptoss)
Sections:
1. **LinkedIn DM** (CTO target, 3 varyant: cold/warm/refer)
2. **Twitter thread** (8-tweet build-in-public, dogfooding focus)
3. **Hacker News Show HN** (title + body draft, comment guidelines)
4. **Cold email** (3 varyant: tech founder, indie hacker, enterprise CTO)
5. **Reddit r/selfhosted + r/ClaudeAI** (community-friendly tone)
6. **Personal network** (referral request)
7. **Demo video script** (3-min Loom outline)

1 test: doc exists + sections + min 1000w.

### Modul D — Status Page Enhanced
**Patch:** `app/api/status_page.py` + `app/static/status.html`
- Ek alanlar: `licenses_active`, `mrr_estimate_usd`, `signups_24h`, `last_payment_at`
- Public version (no auth): `/v1/status` minimal
- Admin version: `/v1/admin/status/full` (Bearer admin) — full metrics + recent events
- HTML auto-refresh 30s

4 test: public minimal shape, admin full shape, auth required, refresh interval.

### Modul E — Beta Admin Queue + Approve Flow
**Yeni:** `app/api/beta_admin.py`
- `GET /v1/admin/beta/queue?status=pending` — Bearer admin
- `POST /v1/admin/beta/{request_id}/approve` — JWT generate + email send + Discord notify
- `POST /v1/admin/beta/{request_id}/reject` — reason field + email
- 4 test (auth, list, approve flow, reject flow)

### Modul F — Discord Beta Flow Integration
**Patch:** `app/integrations/discord_webhook.py`
- `notify_beta_request(email, name, use_case)` — admin channel
- `notify_beta_approved(license_jti, email)` — log channel
- `notify_milestone(metric, value)` — örneğin "10 beta signup", "first paid customer"
- 3 test (webhook payload, no-op when env empty, milestone trigger)

### Modul G — Public Landing CTA
**Patch:** `core/landing/app/page.tsx` (varsa) ve/veya yeni `core/landing/app/beta/page.tsx`
- "Request Beta Access" button → form (email, name, company, use_case)
- POST `/v1/beta/request`
- Confirmation page after submit
- 3 vitest (form render, submit, validation)

### Modul H — `beta_metrics` MCP Tool
**Yeni:** `app/mcp/tools/beta_tools.py`
- `beta_metrics()` — pending count, approved count, conversion rate (approved → paid), recent signups (24h)
- 2 test
- Tool count 119 → **120**

---

## 3. Test Stratejisi (25+ test)

| Modül | Test |
|---|:-:|
| A beta request | 5 |
| B welcome sequence | 8 |
| C outreach doc | 1 |
| D status enhanced | 4 |
| E admin queue | 4 |
| F discord flow | 3 |
| G public CTA (frontend) | 3 vitest |
| H beta_metrics MCP | 2 |
| Tool count guard | 1 update |
| **TOPLAM** | **27 backend + 3 frontend = 30** |

Backend: 577 → **604**. Frontend: 33 → **36**. Tool: 119 → **120**.

---

## 4. Smoke Evidence (`/tmp/abs-031-smoke/evidence/`)

1. `01_beta_request_flow.json` — request → queue → approve → license
2. `02_email_sequence_tick.json` — 5 email lifecycle dry-run
3. `03_outreach_templates_present.json` — sections doğrulama
4. `04_status_admin_full.json` — admin endpoint response
5. `05_discord_milestone_payload.json` — webhook embed
6. `06_beta_metrics_mcp.json` — MCP tool response

---

## 5. Adım Adım

```
1. baseline pytest 577 + tool 119
2. Modul A: beta_portal + queue + 5 test
3. Modul B: 5-email × 3-lang (qwen32b TR+ES delegate, ~9 file × 600w ~5400w toplam) + scheduler + 8 test
4. Modul C: outreach-templates.md (gptoss EN ~1200w) + 1 test
5. Modul D: status enhanced + 4 test
6. Modul E: admin queue + 4 test
7. Modul F: discord flow + 3 test
8. Modul G: landing CTA + 3 vitest
9. Modul H: beta_metrics MCP + count 119→120 + 2 test
10. 6 smoke evidence
11. summary + completed/
12. memory snapshot 031
```

## 6. DoD

```
[ ] 8 modül A-H tamam
[ ] pytest 604 (+27)
[ ] vitest 36 (+3)
[ ] tool 120 (+1)
[ ] 6 smoke evidence
[ ] regression sıfır
[ ] summary + completed/
[ ] memory snapshot 031
```

## 7. Notlar

1. **Beta queue persistence** — SQLite `beta_requests` table boot'ta create_all, mevcut License ile foreign key.
2. **Welcome email TR/ES** — qwen32b ile çevir, back-translate doğrulama (qual_translate pattern 023).
3. **Outreach gptoss** — EN, brand-aligned ton (Automatia BCN voice — "honest, technical, data-driven, no hype").
4. **Discord webhook secret** — ABS_DISCORD_WEBHOOK_URL env, vault'tan oku (013).
5. **Memory snapshot:** task sonu `session_resume_state_20260427_031.md`.
