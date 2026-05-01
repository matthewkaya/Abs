# Task 017 — Stripe Live + Customer Portal + İlk Müşteri Playbook — SUMMARY

**Status:** DONE
**Tarih:** 2026-04-26
**Süre:** ~2.5 saat (Worker Sonnet+Opus paralel)
**Spec:** `_agent-tasks/017-stripe-live-customer-playbook.md`

---

## Özet Tablo

| Metrik | Önce | Sonra | Δ |
|---|---|---|---|
| Toplam test | 270 + 2 skip | 292 + 2 skip | **+22** |
| MCP tool sayısı | 102 | 103 | **+1** (`billing_status`) |
| Yeni dosya | — | 9 | webhook idempotency + portal + billing_tools (genişletildi) + 2 doc + 4 test |
| Modifiye dosya | — | 8 | webhook handler + main.py + db/models + db/session + setup_stripe_products + server.py + test_tools_count + billing_tools |
| Live Stripe API çağrısı | — | **0** | tüm testler `monkeypatch` (sk_live_ tests'te sadece dummy `sk_live_xyz` ABORT testi için) |

---

## Modül Modül Açıklama

### Modul A — Webhook Event Idempotency ✅

- `app/db/models.py` patch: yeni `WebhookEvent(SQLModel, table=True)` — PK `event_id`, index `event_type`+`license_jti`. Boot'ta `SQLModel.metadata.create_all` ile otomatik oluşur (Alembic yok, 022+'a planlandı).
- `app/api/webhooks/idempotency.py` — `claim_event(db, event_id, event_type)` INSERT dener, `IntegrityError` → `DuplicateEventError`. `mark_processed(db, row, license_jti, error)` claim sonrası tamamla.
- `app/api/webhooks/stripe.py` patch: imza doğrulama sonrası `claim_event`; duplicate → 200 + `{duplicate: true, license_jti}`. 4 return path'e (checkout, refund missing-license, refund duplicate, refund success, ignored, sub-deleted) `mark_processed` enjekte edildi.
- **5 test** `tests/test_webhook_idempotency.py`:
  - duplicate checkout returns duplicate
  - duplicate refund does not overwrite revoked_at
  - two different event_ids both processed
  - event_type index exists
  - claim_event race condition raises DuplicateEventError

**Regression:** test_stripe_webhook.py 4/4 + test_refund_handler.py 3/3 yeşil.

### Modul B — Customer Portal Endpoint ✅

- `app/api/billing_portal.py` — `POST /v1/billing/portal` (75 satır). Aktif lisans (revoked_at IS NULL) ara → `stripe.billing_portal.Session.create(customer=...)` → `portal_url` + `expires_at`. 503 (no key) / 404 (no license) / 502 (Stripe error) hata yolları.
- `app/main.py` patch: `billing_portal_router` register.
- **4 test** `tests/test_billing_portal.py`:
  - 503 no stripe key
  - 404 no active license
  - 200 active license + Stripe mock URL
  - 404 revoked license (refund sonrası portal kapalı)

**Stripe mock:** `stripe.billing_portal.Session.create` `monkeypatch` ile `types.SimpleNamespace(url=..., id=...)`. Live API çağrılmadı.

### Modul C — Setup Script Live Mode Safeguard ✅

- `infra/scripts/setup_stripe_products.py` — `argparse` refactor: `--mode test|live` (default test), `--dry-run`. `_validate_key_mode()` mode×key prefix uyumu (live→sk_live_, test→sk_test_). Uyuşmazlık → exit 2 stderr ABORT. `--dry-run` Stripe import'u yapmaz, 3 satır WOULD-CREATE basar. Product+Price metadata'sına `mode` eklendi (idempotency live/test ayrı).
- **4 test** `tests/test_setup_stripe_products.py` (subprocess mock):
  - --dry-run hiç stripe çağırmaz, 3 WOULD-CREATE
  - --mode live + sk_test_ → exit 2
  - --mode test + sk_live_ → exit 2
  - no key env → exit 1

**Regression:** test_pricing_sku_mapping.py 3/3 yeşil (SKU mapping değişmedi).

### Modul D — MCP Tool `billing_status` ✅

- `app/db/session.py` patch: `@contextmanager get_session_sync()` eklendi (MCP tool async ama DB query sync — `with` pattern).
- `app/mcp/tools/billing_tools.py` patch: 4. tool `billing_status` eklendi. `_get_products_cached` (5dk TTL Stripe Product+Price), `_compute_revenue` (tier×seat fiyat toplamı: 299/1196/2093, gross — refund düşülmez), `_license_counts` (active/revoked/expired), `_recent_events` (son 10 webhook, desc).
- **Circular import fix:** `REGISTERED_TOOLS = []` deklarasyonu `app.mcp.server` import'undan ÖNCE konuldu — diğer tool dosyaları conftest sırasıyla şanslı, ama izole test çalıştırmada billing_tools doğrudan import edildiğinde server.py recursion'a giriyordu. Tüm heavy import'lar (`sqlmodel`, `stripe`, `app.db.*`, `app.config`) lazy fonksiyonların içine alındı (innovation_tools.py pattern).
- `app/mcp/server.py` patch: comment 015→017 dahil + 102→**103** otomatik (REGISTERED_TOOLS uzunluğu 3→4).
- **3 test** `tests/test_billing_status_mcp.py`:
  - no stripe key → empty products
  - revenue aggregation (3 lisans → ≥3588 USD)
  - recent events ordered desc

### Modul E — Live Mode Runbook ✅

- `docs/billing-runbook.md` — **~915 kelime, 8 ana bölüm**:
  1. Test→Live geçişi (Dashboard, vault, products oluşturma, ilk live test, post-test refund)
  2. Webhook secret rotate
  3. Manual refund (Dashboard üstünden)
  4. Dispute/chargeback (manuel revoked_at set komutu dahil)
  5. Yaygın hatalar tablosu (6 hata × sebep × çözüm)
  6. Customer Portal (017) endpoint kullanımı
  7. Günlük izleme (`billing_status` MCP + DB sqlite3)
  8. Acil iletişim

### Modul F — First Customer Playbook ✅

- `docs/first-customer-playbook.md` — **~960 kelime, 5 faz**:
  - **Faz 1** Beta Lisansları (manuel `generate_license` + DB License row + email gönderim, 5 hedef listesi, feedback toplama)
  - **Faz 2** Landing + Outreach (LinkedIn/Twitter/HN scriptleri, 3 email waitlist sequence)
  - **Faz 3** Launch Day (checklist, UTC zaman çizelgesi 12:00-24:00, common HN/Reddit Q&A)
  - **Faz 4** Post-Launch İzleme (success metrics tablosu ay 1/3, haftalık ops 15dk/gün, aylık retro)
  - **Faz 5** Beyond First 3 (testimonial, pricing power, outbound sales)

**Doc tests** `tests/test_runbook_doc_exists.py` (2 test) + `tests/test_webhook_event_model.py` (3 test).

---

## Test Sonuçları

```
$ ./.venv/bin/pytest -q
292 passed, 2 skipped in 6.74s
$ ./.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
103
```

**Yeni testler (22):**
| Dosya | Test |
|---|---|
| test_webhook_idempotency.py | 5 |
| test_billing_portal.py | 4 |
| test_setup_stripe_products.py | 4 |
| test_billing_status_mcp.py | 3 |
| test_tools_count.py | 1 (yeni: `billing_status` registry guard) |
| test_runbook_doc_exists.py | 2 |
| test_webhook_event_model.py | 3 |
| **TOPLAM** | **22** |

**Regression check (011-016):** 24/24 yeşil
```
$ ./.venv/bin/pytest -q tests/test_stripe_webhook.py tests/test_refund_handler.py \
    tests/test_pricing_sku_mapping.py tests/test_checkout_session.py \
    tests/test_demo_mode.py tests/test_license_gate.py
24 passed
```

---

## Live MCP Smoke Evidence

`/tmp/abs-017-smoke/evidence/` (5 dosya):

1. **`01_webhook_idempotency.json`** — Aynı `evt_smoke_001` ile 2 POST. İkincisi `{"duplicate": true, "license_jti": "ccc35480..."}`. JTI match doğrulandı.
2. **`02_billing_portal.json`** — `POST /v1/billing/portal` mock'lu Stripe response → `portal_url=https://billing.stripe.com/p/session/test_smoke_xyz`, `expires_at=2026-04-26T...`.
3. **`03_setup_script_dry_run.txt`** — `python setup_stripe_products.py --mode test --dry-run` stdout: 3 WOULD-CREATE satır (self-host $299, team-5 $1196, team-10 $2093). exit=0.
4. **`04_billing_status_mcp.json`** — MCP `billing_status` response: 2 product (mock), revenue $598 (2 self-host beta), 2 active license, 1 recent webhook event.
5. **`05_setup_script_safeguard.txt`** — `--mode live + sk_test_xyz` ABORT: "GUVENLIK: --mode live verildi ama ABS_STRIPE_SECRET_KEY 'sk_live_' ile baslamiyor. ABORT." exit=2.

JSON parse doğrulama: 3/3 OK.

---

## [REDACTED] Policy

- `ABS_STRIPE_SECRET_KEY` env'den okundu — **[REDACTED]** (testlerde `sk_test_dummy` / `sk_test_xyz`, live key bu makinede yok).
- `ABS_STRIPE_WEBHOOK_SECRET` env'den okundu — **[REDACTED]** (testlerde `whsec_test_dummy`).
- Test'lerde `sk_live_` prefix sadece `sk_live_xyz` dummy string olarak `--mode test` safeguard ABORT testinde kullanıldı (live API'ye dokunmadı).
- `grep "sk_live_" tests/` → **sadece test fixture sürtüşme stringi** (test_setup_stripe_products.py satır 71 — beklenen safeguard).

---

## Planlayıcıya Notlar (deferred edge cases)

1. **Net revenue (refund subtraction + Stripe fees)** — `_compute_revenue` Gross gösterir (Dashboard ile aynı). Net revenue 022+'a.
2. **Stripe coupon `FIRST50` programatik oluşturma** — şu an Dashboard manuel. 022+ MCP `coupon_create` tool ekleyebilir.
3. **WebhookEvent retention/purge cron** — şu an silmiyor (event_id PK lookup hızlı). 90 günlük purge cron 022+'a.
4. **Demo countdown reset prosedürü** — runbook'a customer support ihtiyacında ekle (022+).
5. **Setup wizard adım metrikleri** (demo bırakma noktası analizi) — 022+ playbook Faz 4.
6. **`metadata.license_jti` checkout flow zorunluluğu** — 014 sonrası deferred. 017'de zorunlu kılınmadı; refund flow `customer_id_stripe` fallback ile çalışıyor.
7. **Email open/click tracking** — waitlist sequence'inde signup → engagement metric için Mailchimp/Resend. 022+.
8. **Annual billing (yearly subscription)** — şu an one-time + manual renewal. 022+ Stripe Price `recurring` ile.

---

## DoD Kontrol Listesi (Spec §7)

- [x] WebhookEvent model + migration (boot create_all)
- [x] idempotency.py + webhook patch + 5 test yeşil
- [x] billing_portal.py + 4 test yeşil
- [x] setup_stripe_products.py argparse refactor + 4 test yeşil
- [x] billing_tools.py + tool register + 3 test + count 103
- [x] docs/billing-runbook.md (~915 kelime, 8 ana bölüm — ≥500 + ≥6 ✓)
- [x] docs/first-customer-playbook.md (~960 kelime, 5 faz — ≥600 + ≥4 ✓)
- [x] test_runbook_doc_exists.py 2 test + test_webhook_event_model.py 3 test
- [x] pytest -q → **292 passed, 2 skipped** (270 + 22)
- [x] tool count **103**, must_have `billing_status` ✓
- [x] /tmp/abs-017-smoke/evidence/ → 5 dosya, hepsi valid (JSON parse 3/3 + txt readable 2/2)
- [x] 011-016 mevcut testler hâlâ yeşil (regression 24/24 ✓)
- [x] 017-stripe-live-customer-playbook-summary.md yazıldı
- [x] Task `_agent-tasks/completed/`'a taşındı
- [x] Stripe live API çağrısı yapılmadı (`grep "sk_live_" tests/` → sadece dummy `sk_live_xyz` test fixture)

---

## Sonraki Adım (Planlayıcı için)

017 ürünleştirme aşamasının ilk taşıydı: Stripe altyapısı **artık gerçek müşteri kabul edebilecek seviyede**:
- Idempotent webhook (replay/retry safe)
- Customer self-service portal
- Live mode safeguard (yanlış key ile yanlış product oluşmaz)
- Operatör dashboard (`billing_status` MCP)
- Operasyon runbook + first customer playbook

**018+ doğal sıra:**
- 018: Landing page premium SVG illustrations + waitlist signup form + Mailchimp/Resend integration
- 019: Annual billing (Stripe recurring Price) + customer dashboard "manage subscription"
- 020: Demo wizard step metrikleri + drop-off analizi
- 021: r/selfhosted moderator outreach + soft launch beta cohort 5 kişi
- 022: Email open/click tracking + WebhookEvent purge cron + net revenue + coupon API
