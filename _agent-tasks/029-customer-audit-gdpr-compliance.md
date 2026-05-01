# Task 029 — Customer Audit Log + GDPR Compliance Foundation

**Status:** READY (Worker autonomous mode — third of 3-task chain 027→028→029)
**Tahmini süre:** 4-5 saat

## ⚠️ DELEGATION KRİTİK — 5H CONTEXT LIMIT

029'da 4 büyük doc var (toplam ~5200 kelime):
- `data-retention-policy.md` (~1200w) → **ZORUNLU** `ask "..." gptoss`
- `dpa-template.md` (~2000w, AB Article 28 uyumlu) → **ZORUNLU** `ask "GDPR Article 28 DPA template EN sections..." gptoss` (legal accuracy)
- `subprocessors.md` (~400w) → `ask "..." qwen32b`
- `privacy-policy.md` GDPR sections (~1600w) → `ask "..." gptoss`

Her birini delegate et, çıktıyı Write tool ile dosyaya kaydet. **Self-write yasak** (token israfı, 5h limit risk).

i18n için TR/ES çevirileri zorunlu `ask "..." qwen32b` (zaten 023'te öğrendin).
**Bağımlı task'lar:** 011 (License + Webhook), 013 (Vault), 017 (Webhook idempotency), 027 (Vault audit), 028 (Webhook security)
**Hedef:** Müşteri-facing audit log + GDPR compliance temelleri (DPA, data export, right-to-erasure, consent tracking, retention policy). Enterprise satışın olmazsa olmazı — SOC 2 minimum + GDPR ready foundation.

---

## 0. Bağlam

010-028 boyunca müşteri verileri toplandı (License, WebhookEvent, ConnectedSecret, EmailQueue, AuditLog) ama:
- **Customer-facing audit log** yok (kullanıcı kendi erişim/aksiyon geçmişini göremez)
- **GDPR data export** endpoint yok (right of access, Article 15)
- **Right to erasure** (Article 17) yok — kullanıcı silinmek istediğinde manuel
- **Consent tracking** yok (legal basis for processing kayıtsız)
- **Retention policy** dokümante değil (GDPR Article 5)
- **DPA template** (Data Processing Agreement) yok
- **Subprocessor list** (Anthropic, Stripe, vb.) yayınlanmamış

Toplantıda CTO sorduğunda: "GDPR uyumlu mu? SOC 2 var mı? DPA imzalayacağız" — şu an cevap "skeleton var, tam değil." Bu task **enterprise-ready** seviyeye çıkarır.

---

## 1. Amaç (DoD)

- [ ] **Customer audit log endpoint** — `GET /v1/me/audit-log` (kendi geçmiş)
- [ ] **GDPR data export** — `POST /v1/me/data-export` (asynk job, JSON ZIP indirme)
- [ ] **Right to erasure** — `DELETE /v1/me/account` (30 gün retention sonra purge cron)
- [ ] **Consent tracking** — `Consent` model + checkout/setup flow'unda capture
- [ ] **Retention policy doc** — `docs/data-retention-policy.md` (~1200 kelime EN)
- [ ] **DPA template** — `docs/legal/dpa-template.md` (~2000 kelime, EN, AB GDPR uyumlu)
- [ ] **Subprocessor list** — `docs/legal/subprocessors.md` + `/v1/legal/subprocessors` endpoint
- [ ] **Privacy policy update** — `docs/legal/privacy-policy.md` (GDPR sections eklendi)
- [ ] **MCP tool:** `compliance_status` — current GDPR/SOC 2 readiness check
- [ ] 35+ yeni test, pytest 526 → ~563
- [ ] Tool count 112 → 113
- [ ] 6 smoke evidence

---

## 2. Modüller

### Modul A — Customer Audit Log (per-customer)
**Yeni:** `app/db/models.py` patch — `CustomerAuditEntry` SQLModel:
- `id, license_jti, action, resource, ts, ip_address (hashed), user_agent_short`
- Index: `(license_jti, ts DESC)` for fast user history query
- Action enum: `login, license_activate, key_added, key_rotated, data_export, account_delete_request, ...`

**Yeni endpoint:** `app/api/me_audit.py`
- `GET /v1/me/audit-log?limit=50&offset=0` — JWT-auth (license_key Bearer)
- Pagination, son 90 gün
- IP hash (SHA-256(ip + secret)) — privacy preserve
- 5 test (pagination, auth fail, empty, filter by action, retention boundary)

**Tracker integration:**
- `app/api/license.py::activate` → audit entry
- `app/api/smart_link.py::api_key` → audit entry
- `app/api/billing_portal.py` → audit entry
- 4 test (entry oluşma, content shape, idempotent)

### Modul B — GDPR Data Export
**Yeni:** `app/api/me_data_export.py`
- `POST /v1/me/data-export` — async job start (job_id döner)
- `GET /v1/me/data-export/{job_id}` — status + download URL
- ZIP içeriği:
  - `license.json` (License row + payload)
  - `audit_log.jsonl` (CustomerAuditEntry filtered)
  - `webhook_events.jsonl` (related events)
  - `connected_secrets.json` (provider names only, NOT keys)
  - `email_queue.jsonl` (gönderilmiş email metadata)
  - `consents.jsonl` (Consent records)
  - `README.txt` (içerik açıklama, GDPR Article 15 compliance)
- Background job (Celery yoksa simple `BackgroundTasks` FastAPI), 5dk içinde tamamlanır
- ZIP encrypted (kullanıcının email + JTI'den derived key, AES-256)
- 7 test (job lifecycle, ZIP content, encryption, expired download, multi-license edge)

### Modul C — Right to Erasure (Account Delete)
**Yeni endpoint:** `app/api/me_account.py::delete_account`
- `DELETE /v1/me/account` — JWT-auth + confirmation token (email link)
- 30 gün retention (geri alma penceresi):
  - `License.scheduled_delete_at = now + 30d`
  - Ek aksiyonlar block (refund flow korunur)
- `infra/scripts/purge_deleted_accounts.py` — daily cron, scheduled_delete_at < now → tam purge:
  - License row delete
  - CustomerAuditEntry delete
  - WebhookEvent anonymize (email hash, jti kalır integrity için)
  - ConnectedSecret delete + vault entry purge
  - EmailQueue ilişkili rows delete
- Audit entry: `action: "account_purged_full"` (after retention)
- 6 test (delete schedule, undo within 30d, purge runs, idempotent purge, refund-after-delete)

### Modul D — Consent Tracking
**Yeni:** `app/db/models.py` patch — `Consent` model:
- `id, license_jti, consent_type, granted_at, withdrawn_at, version, source`
- Types: `terms_of_service, privacy_policy, marketing_emails, telemetry, dpa_acceptance`
- Source: `checkout, setup_wizard, settings_page`
- Integration:
  - Checkout flow: `terms_of_service` + `privacy_policy` zorunlu
  - Setup wizard: `marketing_emails` + `telemetry` opt-in
- 5 test (grant, withdraw, version tracking, multi-consent, GDPR Article 7 compliance)

### Modul E — Retention Policy Doc
**Yeni:** `docs/data-retention-policy.md` (~1200 kelime EN)
- Section 1: Data categories (License, AuditLog, WebhookEvent, ConnectedSecret, ...)
- Section 2: Retention period each category (License: lifetime + 7 years post-delete; AuditLog: 90 days; WebhookEvent: 7 days; vb.)
- Section 3: Legal basis (contract, legitimate interest, consent)
- Section 4: Deletion process (auto cron + manual request)
- Section 5: Exceptions (legal hold, dispute resolution)
- 1 test (sections + min 1000 kelime + retention table presence)

### Modul F — DPA Template
**Yeni:** `docs/legal/dpa-template.md` (~2000 kelime EN, AB GDPR Article 28 uyumlu)
- Article 1: Definitions
- Article 2: Subject matter, duration, nature, purpose
- Article 3: Categories of data subjects + personal data
- Article 4: Obligations of data processor (Automatia BCN)
- Article 5: Sub-processors (whitelist + customer notification)
- Article 6: Data subject rights assistance
- Article 7: Security measures
- Article 8: Breach notification (72h rule)
- Article 9: Audit rights
- Article 10: Return / deletion of data
- Annex: Subprocessor list, security measures detail
- 1 test (sections + min 1800 kelime)

### Modul G — Subprocessor List
**Yeni:** `docs/legal/subprocessors.md` + `app/api/legal.py::subprocessors`
- Mevcut subprocessors:
  - **Anthropic** (Claude API) — US, GDPR-compliant DPA
  - **Stripe** (payment processing) — US/Ireland, PCI DSS Level 1
  - **Cloudflare** (Workers AI optional) — US/Global, GDPR
  - **Google** (Gemini API optional) — US, GDPR
  - **Groq** (Inference) — US, standard contractual clauses
  - **Cohere** (Rerank optional) — Canada, GDPR-compliant
- `/v1/legal/subprocessors` — JSON list (public, no auth)
- Update tracking: `last_updated_at`, change notification email subscription
- 4 test (list shape, public access, subscription endpoint, change history)

### Modul H — Privacy Policy GDPR Sections
**Patch:** `core/landing/app/privacy/page.tsx` extend (mevcut 018'de var)
- Yeni bölümler:
  - Article 13/14 (information at collection)
  - Article 15 (right of access — link to /me/data-export)
  - Article 16 (rectification)
  - Article 17 (erasure — link to /me/account delete)
  - Article 18 (restriction)
  - Article 20 (data portability)
  - Article 21 (objection)
  - Article 22 (automated decision-making — N/A, ABS no automated profiling)
- 3 vitest (sections render, links present, lang switching)

### Modul I — `compliance_status` MCP Tool
**Yeni:** `app/mcp/tools/compliance_tools.py`
- `compliance_status()` output:
  ```python
  {
    "gdpr": {
      "data_export_endpoint": True,
      "right_to_erasure": True,
      "consent_tracking": True,
      "retention_policy_doc": True,
      "dpa_template": True,
      "subprocessor_list": True,
      "privacy_policy_updated_at": "2026-04-27"
    },
    "soc2": {
      "audit_log_immutable": vault_audit_chain_ok,
      "access_control": "Bearer token + JWT",
      "encryption_at_rest": "sops + age",
      "encryption_in_transit": "TLS 1.3 (Caddy)",
      "incident_response": "runbook doc present",
      "readiness_score": 0.0..1.0
    },
    "open_gaps": [...],  # eksik kalan compliance maddeleri
  }
  ```
- 3 test
- Tool count 112 → **113**

---

## 3. Test Stratejisi (35+ test)

| Modül | Test |
|---|:-:|
| A audit log | 5 + 4 tracker |
| B data export | 7 |
| C right to erasure | 6 |
| D consent | 5 |
| E retention doc | 1 |
| F DPA template | 1 |
| G subprocessors | 4 |
| H privacy policy (frontend) | (3 vitest) |
| I compliance_status MCP | 3 |
| Tool count guard | (1 update) |
| **TOPLAM (backend)** | **36** |
| **TOPLAM (frontend)** | **+3** |

Backend: 526 → **562** (+36). Frontend: 27 → **30** (+3).

---

## 4. Smoke Evidence (`/tmp/abs-029-smoke/evidence/`)

1. `01_audit_log_pagination.json` — kullanıcı audit log API
2. `02_data_export_zip.json` — async job lifecycle + ZIP içerik manifest
3. `03_account_delete_flow.json` — schedule + undo + purge
4. `04_consent_tracking.json` — checkout flow consent capture
5. `05_subprocessor_list.json` — `/v1/legal/subprocessors` response
6. `06_compliance_status_mcp.json` — readiness score + gaps

---

## 5. Adım Adım

```
1. baseline pytest 526 + tool 112
2. Modul A: customer audit + tracker + 9 test
3. Modul B: data export async + 7 test
4. Modul C: right to erasure + 6 test
5. Modul D: consent + 5 test
6. Modul E: retention doc (qwen32b/gptoss EN delegation, ~1200w)
7. Modul F: DPA template (gpt-oss EN, ~2000w, AB GDPR-uyumlu)
8. Modul G: subprocessors + endpoint + 4 test
9. Modul H: privacy policy frontend + 3 vitest
10. Modul I: compliance_status MCP + count 112→113 + 3 test
11. Smoke 6 evidence
12. summary + completed/
13. memory snapshot 029
14. /tmp/abs-autonomous-success-027-029.md final chain raporu
```

## 6. DoD Checklist

```
[ ] 9 modül A-I tamam
[ ] pytest 562 (+36 from 526 baseline)
[ ] vitest 30 (+3 privacy policy)
[ ] tool 113
[ ] 6 smoke evidence
[ ] regression sıfır (010-028)
[ ] Audit log per-customer + IP hashed
[ ] Data export async + encrypted ZIP
[ ] Right to erasure 30d retention + purge cron
[ ] Consent capture checkout + setup
[ ] DPA template AB GDPR Article 28 uyumlu
[ ] Subprocessor list public endpoint
[ ] Privacy policy GDPR Articles 13-22
[ ] compliance_status MCP score >0.8
[ ] summary + completed/
[ ] memory snapshot 029
[ ] chain final report
```

## 7. Worker Notları

1. **Audit log IP hashing** — `hashlib.sha256((ip + settings.audit_ip_salt).encode()).hexdigest()[:16]`. Salt env, rotate edilmez (sabit hash join için).
2. **Data export ZIP encryption** — `cryptography.fernet.Fernet` symmetric, key derived from `(license_jti + customer_email).encode()`. Kullanıcı download için aynı email/license girer.
3. **Account delete confirmation** — email gönderilir, link 24h geçerli token (JWT). Click → schedule. Schedule iptal: kullanıcı 30 gün içinde tekrar login + cancel butonu.
4. **Consent versioning** — `consent_type+version` composite key. Yeni TOS yayınlandığında re-consent.
5. **DPA template** legal review GEREKİR — task'ta "template" oluşturuluyor, gerçek imzalama öncesi avukat kontrol şart. README'ye notu ekle.
6. **Subprocessor list update** — mevcut listeyi gpt-oss ile doğrula (Anthropic Stripe Cloudflare Google Groq Cohere'in 2026 GDPR statusları).
7. **Privacy policy multi-lang** — 023'te i18n vardı, EN/TR/ES 3 versiyon update edilir.
8. **compliance_status readiness score** — formula: (gdpr_endpoints_present + soc2_evidence) / total_checks. Score 1.0 = enterprise-ready.
9. **Backward compat:** mevcut License, WebhookEvent davranışı değişmez. Yeni table'lar (CustomerAuditEntry, Consent) boot'ta create_all idempotent.
10. **Performance:** audit log query (license_jti + last 30d) <50ms with index.
11. **Memory snapshot:** task sonu `session_resume_state_20260427_029.md`.
12. **Chain final:** 029 bittikten sonra `/tmp/abs-autonomous-success-027-029.md` 3 task özeti yaz.
