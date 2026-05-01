# Task 019 — Onboarding Email Sequence (5 Email + Scheduler + Cron)

**Status:** READY (Worker)
**Tahmini süre:** 2-3 saat
**Bağımlı task'lar:** 011 (license_delivery email), 012 (refund + expiration template), 013 (vault SMTP secrets), 017 (webhook idempotency)
**Hedef sonuç:** Yeni müşteri lisans aldıktan sonra otomatik 5-email serisi: welcome (1h), walkthrough (24h), first-success (3d), expiry-warning (10d demo), recovery (7d post-expiry).

---

## 0. Bağlam

011'de `send_license_email` SMTP fallback console hazır. 012'de `license_refund.html` + `license_expired.html` template'leri eklendi. Şu an müşteri lisans aldığında **sadece bir email** gider (license_delivery). Onboarding kayıp:
- Setup başarısız olursa 24h'da hatırlatma yok
- İlk MCP tool çağrısı yapıldığında pekiştirme yok
- Demo countdown 14 gün → uyarı yok (sadece panel banner)
- Lisans expired olursa kurtarma email yok

019: 5 email template + scheduler (DB-backed, JSONL queue) + cron worker.

---

## 1. Amaç (DoD)

- [ ] 5 yeni email template (HTML, brand-aligned, mobile-responsive)
- [ ] `EmailQueue` SQLModel table (id, license_jti, kind, scheduled_at, sent_at, error)
- [ ] `app/email/scheduler.py` — schedule + tick (cron her 5dk)
- [ ] Webhook `checkout.session.completed` sonrası otomatik 5 email schedule
- [ ] First-success trigger — `tracker.bump()` ilk MCP tool çağrısında schedule
- [ ] Demo countdown background task (`app/licensing/demo.py::status` ile sync)
- [ ] License expiry trigger — günlük cron 7 gün önce ve gün
- [ ] MCP tool: `email_queue_status` (recent 50 email, status breakdown)
- [ ] 18 yeni test (toplam 292 → 310)
- [ ] Tool count 103 → 104
- [ ] 4 smoke evidence

---

## 2. Modüller

### Modul A — Email Templates (5 yeni)
`core/backend/app/email/templates/` altına:
1. `welcome.html` — "Hoş geldin, ABS hazır" (1h sonra trigger)
2. `walkthrough.html` — "Setup wizard rehberi" (24h)
3. `first_success.html` — "İlk MCP tool'unu çalıştırdın!" (ilk bump'ta trigger)
4. `expiry_warning.html` — "Demo 4 gün kaldı / Lisans 7 gün kaldı" (countdown)
5. `recovery.html` — "Lisansın doldu, geri gel" (expired sonrası 7d)

Her template:
- `<!-- subject: ... -->` ilk satır
- Brand: Automatia ABS (mavi gradient header), JetBrains Mono kod blokları
- CTA buton (renew / setup / docs)
- Unsubscribe link (footer, hard-coded `/v1/email/unsubscribe?token=...`)

Delegation: `ask "..." qwen32b` ile metinler üret, sonra worker render kontrolü.

### Modul B — EmailQueue Model + Scheduler
`app/db/models.py` patch:
```python
class EmailQueue(SQLModel, table=True):
    __tablename__ = "email_queue"
    id: Optional[int] = Field(default=None, primary_key=True)
    license_jti: str = Field(index=True, max_length=64)
    customer_email: str = Field(max_length=256)
    kind: str = Field(max_length=32)  # welcome|walkthrough|first_success|expiry_warning|recovery
    scheduled_at: datetime = Field(index=True)
    sent_at: Optional[datetime] = Field(default=None)
    attempts: int = Field(default=0)
    error: Optional[str] = Field(default=None, max_length=512)
```

`app/email/scheduler.py` (~140 satır):
- `schedule_onboarding(license_jti, email)` — 5 email row insert (welcome+1h, walkthrough+24h, expiry_warning+10d, recovery+21d). first_success trigger'da ayrıca.
- `tick()` — `scheduled_at <= now AND sent_at IS NULL` query, send, mark, exponential backoff retry (max 3)
- `unsubscribe(token)` — JWT verify → DB row update `unsubscribed=True` (kolon eklenmeli)

### Modul C — Webhook Hook
`app/api/webhooks/stripe.py` patch — `checkout.session.completed` sonunda:
```python
from app.email.scheduler import schedule_onboarding
schedule_onboarding(license_jti=payload_dict["jti"], email=email)
```

### Modul D — First-Success Trigger
`app/mcp/tracking.py::bump()` patch:
- Bu license_jti için ilk başarılı tool çağrısıysa (`License.first_tool_call_at IS NULL`):
  - `License.first_tool_call_at = now`
  - `schedule_first_success(license_jti)` — 0-saat delay (immediate)

### Modul E — Cron Worker
`infra/scripts/email_tick.py` — standalone script:
```python
from app.email.scheduler import tick
import sys
sent, failed = tick()
print(f"sent={sent} failed={failed}")
sys.exit(0 if failed == 0 else 1)
```
`docker-compose.yml` patch — yeni service:
```yaml
abs-email-cron:
  build: ./core/backend
  command: ["sh", "-c", "while true; do python infra/scripts/email_tick.py; sleep 300; done"]
  depends_on: [abs-backend]
```

### Modul F — MCP Tool email_queue_status
`app/mcp/tools/email_tools.py` (yeni):
```python
async def email_queue_status() -> dict:
    """Son 50 email kuyrukta + breakdown by status."""
    return {
        "by_status": {"sent": ..., "pending": ..., "failed": ...},
        "by_kind": {"welcome": ..., ...},
        "recent": [...]  # 50 row
    }
```

### Modul G — Unsubscribe Endpoint
`app/api/email_unsubscribe.py`:
- `GET /v1/email/unsubscribe?token=...` → JWT verify (license_jti) → DB unsubscribed=True
- HTML response (basit)

---

## 3. Test Stratejisi (18 test)

| Dosya | Test |
|---|:-:|
| `test_email_templates_render.py` | 5 (her template render + subject parse) |
| `test_email_scheduler.py` | 5 (schedule, tick, retry, backoff, unsubscribe) |
| `test_email_webhook_integration.py` | 2 (checkout → 5 email scheduled) |
| `test_email_first_success.py` | 2 (ilk bump trigger, sonraki bump'lar trigger değil) |
| `test_email_queue_status_mcp.py` | 2 (status response shape, breakdown) |
| `test_tools_count.py` | 1 (103 → 104, must_have email_queue_status) |
| `test_email_unsubscribe.py` | 1 (token verify, DB update) |

Mock SMTP — `monkeypatch` ile `smtplib.SMTP` mock'la, gerçek email gönderme yok.

---

## 4. Smoke Evidence

1. `01_5_emails_scheduled.json` — webhook trigger sonrası DB'de 5 row
2. `02_tick_sends_due_emails.json` — tick() 1 due email send + sent_at set
3. `03_email_queue_status_mcp.json` — MCP tool response
4. `04_unsubscribe_flow.json` — token gen + endpoint hit + DB unsubscribed=True

---

## 5. Adım Adım

```
1. baseline pytest 292 + tool 103
2. Modul A: 5 template (qwen32b ile metin) + 5 test
3. Modul B: EmailQueue model + scheduler.py + 5 test
4. Modul C: webhook hook + 2 test
5. Modul D: first-success trigger + 2 test
6. Modul E: cron worker + docker-compose patch (test edilmez, dosya varlığı)
7. Modul F: email_queue_status tool + 2 test + count 103→104
8. Modul G: unsubscribe endpoint + 1 test
9. Smoke: 4 evidence
10. pytest 310 + tool 104 doğrula
11. summary + completed/
```

## 6. DoD Checklist

```
[ ] 5 template + render test
[ ] EmailQueue table + scheduler tick/retry
[ ] Webhook integration scheduled 5 email
[ ] first_success trigger
[ ] cron worker docker service
[ ] email_queue_status MCP tool
[ ] unsubscribe endpoint
[ ] pytest 310 + tool 104
[ ] 4 smoke evidence
[ ] regression: 011-018 testleri yeşil
[ ] summary + completed/
```

## 7. Worker Notları

1. SMTP_HOST boşsa scheduler tick gerçek email atmaz, console'a yazar (011 pattern). Test bu durumu monkeypatch ile simüle eder.
2. Unsubscribe JWT 1 yıl expiry, secret config'den (`settings.unsubscribe_jwt_secret`).
3. Scheduler tick **idempotent** — `sent_at IS NOT NULL` row'ları skip eder.
4. Recovery email "lisansın doldu" — `License.expires_at < now` AND `revoked_at IS NULL` filtresi.
5. Demo expiry warning 10. günde — demo state file `data_dir/demo_state.json` kontrolü.
6. Email kind'lar enum değil string — flexibility için (sonradan welcome_v2 eklemek kolay).
