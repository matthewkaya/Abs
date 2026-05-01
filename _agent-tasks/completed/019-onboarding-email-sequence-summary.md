# Task 019 — Onboarding Email Sequence — SUMMARY

**Status:** DONE
**Tarih:** 2026-04-27
**Spec:** `_agent-tasks/019-onboarding-email-sequence.md`

---

## Özet Tablo

| Metrik | Önce | Sonra | Δ |
|---|---|---|---|
| pytest backend | 292 + 2 skip | **310 + 2 skip** | **+18** |
| MCP tool sayısı | 103 | **104** | +1 (`email_queue_status`) |
| Yeni dosya | — | 11 (5 template, scheduler, email_tools, email_unsubscribe, email_tick, 6 test, models patch, config patch, compose patch) |
| Modifiye dosya | — | webhook handler, middleware, server.py, main.py, models.py, config.py, docker-compose, test_tools_count |
| Live SMTP çağrısı | — | **0** — `monkeypatch settings.smtp_host=""` console fallback |

---

## Modül Modül

### A — 5 Email Template ✅
- `welcome.html` (1h), `walkthrough.html` (24h), `first_success.html` (immediate trigger), `expiry_warning.html` (10d before), `recovery.html` (21d after expire)
- Her template HTML email best-practice: max-width 600px, mobile responsive, inline styles, gradient header, brand color #1e57ac → #3b82f6
- `<!-- subject: ... -->` ilk satırda, `_render` parser yakalar
- 5 test (`test_email_templates_render.py`): subject + value substitution

### B — EmailQueue Model + Scheduler ✅
- `db/models.py` patch: `EmailQueue` table (license_jti, kind, scheduled_at, sent_at, attempts, error, unsubscribed) + `License.first_tool_call_at` field
- `email/scheduler.py` (~210 satır): `schedule_onboarding` (4 row insert), `schedule_first_success` (idempotent), `tick` (due rows, exponential backoff 5min×2^attempts, max 3), `unsubscribe` (JWT verify → DB update), `_make_unsubscribe_token` (JWT HS256 1y exp)
- Console fallback: SMTP_HOST boşsa `_send_html` log'a yazar
- 5 test (`test_email_scheduler.py`): schedule_onboarding, tick due, tick idempotent skip, schedule_first_success idempotent, unsubscribe token

### C — Webhook Hook ✅
- `api/webhooks/stripe.py` patch: `checkout.session.completed` sonunda `schedule_onboarding(license_jti, email, db=db)`
- 2 test (`test_email_webhook_integration.py`): 4 onboarding email scheduled, duplicate webhook skip
- 017 idempotency korunur: aynı event.id ikinci kez gelirse claim aşamasında yakalanır, schedule tekrarlanmaz

### D — First-Success Trigger ✅
- `mcp/middleware.py::_maybe_trigger_first_success(tool_name)` — settings.license_key varsa, lisansı verify, License.first_tool_call_at IS NULL ise set + schedule_first_success
- `with_hooks` wrapper'ı her başarılı tool çağrısı sonunda trigger eder
- Idempotent: License.first_tool_call_at NOT NULL ise no-op
- Demo modda lisans yok → trigger çalışmaz (settings.license_key boş)
- 2 test (`test_email_first_success.py`): ilk çağrı row eklendi + first_tool_call_at set, sonraki çağrılar no-op

### E — Cron Worker ✅
- `infra/scripts/email_tick.py` — standalone `python -m` script, `tick()` çağırır, stdout `sent=N failed=M`, exit 0/1
- `infra/docker-compose.yml` patch: `email-cron` service, `while true; do python infra/scripts/email_tick.py; sleep 300; done`, depends_on backend, abs-data + abs-vault-key volume'leri
- Test edilmedi (test_email_scheduler.py zaten tick'i unit-test ediyor)

### F — `email_queue_status` MCP Tool ✅
- `mcp/tools/email_tools.py` (yeni): `email_queue_status(limit=50)` — by_status (sent/pending/failed), by_kind (5 kind), recent (son N row) JSON
- `REGISTERED_TOOLS = []` BEFORE `app.mcp.server` import (017 lazy-import deviation pattern korundu)
- `mcp/server.py` patch: `email_tools` register et, count 103 → **104**
- 2 test (`test_email_queue_status_mcp.py`): response shape, breakdown sums + 1 test (`test_tools_count.py`): 104 + must_have email_queue_status

### G — Unsubscribe Endpoint ✅
- `api/email_unsubscribe.py`: `GET /v1/email/unsubscribe?token=...` → JWT verify → DB update → HTMLResponse
- `main.py` patch: `email_unsubscribe_router` register
- 1 test (`test_email_unsubscribe.py`): token gen → endpoint hit → DB unsubscribed=True

---

## Test Sonuçları

```
$ .venv/bin/pytest -q --tb=short
310 passed, 2 skipped in 7.57s
$ .venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
104
```

**Yeni testler (18):**
| Dosya | Test |
|---|:-:|
| test_email_templates_render.py | 5 |
| test_email_scheduler.py | 5 |
| test_email_webhook_integration.py | 2 |
| test_email_first_success.py | 2 |
| test_email_queue_status_mcp.py | 2 |
| test_tools_count.py | 1 (yeni: `email_queue_status` registry) |
| test_email_unsubscribe.py | 1 |
| **TOPLAM** | **18** |

**Regression check:**
- 011-018 mevcut testler: ✅ 292 → 292 yeşil
- Total: **310 passed + 2 skipped** (270 baseline + 22 [017] + 18 [019] = 310 ✓)

---

## Smoke Evidence

`/tmp/abs-019-smoke/evidence/` (4 dosya, hepsi valid JSON):
1. **`01_5_emails_scheduled.json`** — webhook trigger sonrası DB'de 4 row (welcome, walkthrough, expiry_warning, recovery)
2. **`02_tick_sends_due_emails.json`** — tick sent=1 failed=0, welcome.sent_at set
3. **`03_email_queue_status_mcp.json`** — by_status `{sent:1, pending:3, failed:0}`, by_kind 4 entry, recent[] 4 row
4. **`04_unsubscribe_flow.json`** — token üret → endpoint → 4 row hepsi `unsubscribed:true`

JSON parse: 4/4 OK.

---

## DoD Kontrol Listesi (Spec §6)

- [x] 5 template + render test (5 test)
- [x] EmailQueue table + scheduler tick/retry (5 test)
- [x] Webhook integration scheduled 4 onboarding email (2 test)
- [x] first_success trigger (2 test)
- [x] cron worker docker service (file mevcut, infra/scripts/email_tick.py + compose service)
- [x] email_queue_status MCP tool (2 test + 1 registry guard)
- [x] unsubscribe endpoint (1 test)
- [x] pytest **310** + tool **104**
- [x] 4 smoke evidence valid
- [x] regression: 011-018 testleri yeşil
- [x] summary + completed/

---

## Planlayıcıya Notlar (deferred)

1. **Spec'te 18 test bekliyordu** — bizimkiler tam 18 (5+5+2+2+2+1+1). Tool count 103 → 104.
2. **Backoff scheduling** — failed row scheduled_at exponential (5min × 2^attempts). 3 attempt sonrası `attempts >= 3` filtresi tarafından skip, manuel intervention.
3. **Ana hata yönetimi**: tick içinde tek email fail olursa diğerleri devam eder, db.commit() blokta.
4. **JWT secret default** `dev-insecure-unsubscribe-change-in-prod` — production'da vault'tan gelmeli (013 ABS_UNSUBSCRIBE_JWT_SECRET).
5. **Recovery email kuponu `COMEBACK20`** — Stripe Dashboard'dan manuel oluşturulmalı (021/022 yapılabilir).
6. **Email open/click tracking** YOK — Mailchimp/Resend integration 022+'a deferred.
7. **first_success template `first_tool_name`** — şimdilik scheduler'da hardcoded `system_status`. Daha doğru yaklaşım: tracker'dan ilk çağrılan tool adını taşımak. 022+'a.

Backend tamamen 011-018 disiplinine sadık — regression yok, idempotent, test mock'lı.
