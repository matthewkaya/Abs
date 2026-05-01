# Task 027 — Vault Production Hardening (sops/age + Rotation + Audit + Recovery)

**Status:** READY (Worker autonomous mode — first of 3-task chain 027→028→029)
**Tahmini süre:** 4-5 saat
**Bağımlı task'lar:** 013 (sops/age vault temel), 022 (deferred edge cleanup), 023 (smart_link/vault_secrets), 026 (vault encrypt fallback base64)
**Hedef:** 013'te kurulan sops/age vault'ı **production-grade** seviyeye taşı — gerçek sops binary integration, age key rotation, audit log immutable, disaster recovery runbook, key escrow.

---

## 0. Bağlam

013'te sops + age temel kuruldu, 022'de master key separate volume eklendi. AMA:
- **026'da `vault_secrets.py` sops binary yoksa base64 fallback yapıyor** (dev/test OK, production değil)
- **age master key rotation** prosedürü yok (compromise senaryosu)
- **Audit log** mevcut (013) ama immutable değil (silinebilir)
- **Disaster recovery** (master key kayıp) yazılı yok
- **Key escrow** (yedek key güvenli yerde) yok

İnce işçilik gereken konular:
1. sops binary detect + production zorunlu (dev'de fallback OK, prod'da fail-fast)
2. age keypair rotation (yeni key, eski şifreli verileri yeniden encrypt)
3. Audit log SQLite + signed checksum (tamper-evident)
4. Recovery prosedür dokümantasyonu (master key kayıp + bulundu senaryo)
5. Key escrow (1Password / S3 encrypted backup) integration

---

## 1. Amaç (DoD)

- [ ] **sops binary detection** — runtime check, prod'da fail-fast (env: `ABS_VAULT_REQUIRE_SOPS=true`)
- [ ] **Age key rotation endpoint** — `POST /v1/admin/vault/rotate-key` (Bearer admin)
- [ ] **Vault audit log immutable** — SQLite tabloya HMAC checksum, tamper detection
- [ ] **Recovery runbook** — `docs/vault-recovery-runbook.md` (~1000 kelime)
- [ ] **Key escrow setup script** — `infra/scripts/vault_escrow_setup.sh` (1Password CLI veya S3 sse-kms)
- [ ] **MCP tool:** `vault_audit_status` — son 50 vault erişim + integrity check
- [ ] **Disaster scenarios test** — 4 senaryo (key lost, key compromised, vault corrupted, partial restore)
- [ ] 30+ yeni test, pytest 459 → ~492
- [ ] Tool count 110 → 111
- [ ] 6 smoke evidence

---

## 2. Modüller

### Modul A — Sops Binary Detection + Production Fail-Fast
**Patch:** `app/vault/runner.py`
- `_check_sops_binary()` — `which sops` + version check (>=3.7)
- Boot'ta `app.config.settings.vault_require_sops` (default False, prod=True)
- True ise sops yoksa boot fail (`raise RuntimeError`)
- False ise warn log + fallback OK (dev mode)
- 4 test (mock subprocess.run, version parse, fail/warn paths)

### Modul B — Age Keypair Rotation
**Yeni dosya:** `app/vault/rotation.py` (~180 satır)
- `rotate_age_key(reason)` workflow:
  1. Yeni `age-keygen` keypair generate
  2. Eski private key ile tüm `secrets.enc.json` decrypt
  3. Yeni public key ile yeniden encrypt
  4. Eski key escrow'a (encrypted ZIP, parolalı) sakla
  5. Master key dosyasını yeni private ile değiştir
  6. Audit log entry: `{action: "rotate", reason, ts, old_fingerprint, new_fingerprint}`
- Atomic rollback: rotation fail → eski key restore
- 6 test (happy path, decrypt fail, encrypt fail, atomic rollback, fingerprint compute, audit entry)

**Yeni endpoint:** `app/api/vault_admin.py`
- `POST /v1/admin/vault/rotate-key` — Bearer auth (`ABS_ADMIN_TOKEN`)
- Body: `{reason: "scheduled" | "compromise" | "manual"}`
- Async job (rotation 30s+, response immediate + job_id, status endpoint)
- 3 test

### Modul C — Audit Log Immutable (HMAC Tamper Detection)
**Yeni:** `app/vault/audit_chain.py` (~150 satır)
- `VaultAuditEntry` SQLModel — `id, ts, action, actor, target_key, hmac, prev_hmac`
- HMAC chain: her entry'nin `hmac = HMAC-SHA256(secret, entry_data + prev_hmac)`
- `verify_chain()` — tüm entry'leri sırayla doğrula, ilk tamper detect edilen entry rapor
- Boot'ta integrity check (warn log if tamper)
- HMAC secret: `settings.vault_audit_hmac_secret` (separate from main vault key)
- 5 test (happy chain, tamper detection, missing prev_hmac, secret rotation, performance 1000 entries)

### Modul D — Recovery Runbook
**Yeni:** `docs/vault-recovery-runbook.md` (~1000 kelime, EN)
- Senaryo 1: **Master key dosyası silindi** — escrow'dan restore (5 step)
- Senaryo 2: **Master key compromised** — rotation + revoke + audit
- Senaryo 3: **Vault dosyası corrupted** — backup'dan restore (Docker volume snapshot)
- Senaryo 4: **Partial restore** — sadece bazı secret'lar bozuk, diğerleri OK
- Her senaryoda: precheck → recovery steps → verification → post-mortem
- Komut bloğu detaylı (`docker compose exec`, sops, age, openssl)
- 1 test (`test_recovery_runbook_completeness.py`) — markdown'da 4 senaryo + min 800 kelime

### Modul E — Key Escrow Setup Script
**Yeni:** `infra/scripts/vault_escrow_setup.sh` (~150 satır bash)
- 3 escrow opsiyon (kullanıcı seçer):
  1. **1Password CLI:** `op document create --vault "ABS Production" --title "vault-master-key-<date>"`
  2. **S3 SSE-KMS:** `aws s3 cp --sse aws:kms --sse-kms-key-id ...`
  3. **Encrypted ZIP local:** `7z a -p<pwd> escrow-<date>.7z master.key`
- Pre-check (CLI tool installed, credentials valid)
- Post-verify (escrow okunabilir mi)
- Idempotent: aynı tarih için zaten escrow varsa skip
- 2 test (script syntax, opsiyon parse)

### Modul F — `vault_audit_status` MCP Tool
**Yeni:** `app/mcp/tools/vault_tools.py`
- `vault_audit_status()` output:
  ```python
  {
    "audit_chain_integrity": "ok" | "tampered" | "unknown",
    "tampered_entry_id": int | None,
    "total_entries": int,
    "entries_24h": int,
    "by_action": {"encrypt": N, "decrypt": M, "rotate": K},
    "recent": [last 50 entries]
  }
  ```
- 3 test
- Tool count 110 → **111**

### Modul G — Disaster Scenario Tests
**Yeni:** `tests/test_vault_disaster_scenarios.py` (~250 satır)
- Senaryo 1: master key file silindi → rotate gerek, yeni key ile restore
- Senaryo 2: vault corrupt (manuel JSON bozma) → backup'dan restore (escrow flow)
- Senaryo 3: HMAC secret değişti → audit chain re-init (no data loss)
- Senaryo 4: 1 secret bozuk, 9 OK → partial recovery (granular re-encrypt)
- 4 test

---

## 3. Test Stratejisi (30+ test)

| Modül | Test |
|---|:-:|
| A sops detection | 4 |
| B age rotation | 6 + 3 endpoint |
| C audit chain | 5 |
| D runbook | 1 |
| E escrow script | 2 |
| F vault_audit_status MCP | 3 |
| G disaster scenarios | 4 |
| Tool count guard | (1 update) |
| Regression (013 vault tests) | (5 mevcut, korumalı) |
| **TOPLAM** | **28 + 4 = 32** |

Backend: 459 → **491** (+32). Frontend: 27 (değişmez).

---

## 4. Smoke Evidence (`/tmp/abs-027-smoke/evidence/`)

1. `01_sops_detection.json` — version check + dev/prod mode behavior
2. `02_age_rotation_flow.json` — rotation start → done + old fingerprint stored
3. `03_audit_chain_integrity.json` — 100 entry chain + tamper detect demo
4. `04_recovery_runbook_validation.json` — markdown sections check
5. `05_escrow_setup_dry_run.txt` — script options output
6. `06_disaster_partial_recovery.json` — senaryo 4 result

---

## 5. Adım Adım

```
1. baseline pytest 459 + tool 110
2. Modul A: sops detection + 4 test
3. Modul B: rotation + endpoint + 9 test
4. Modul C: audit chain HMAC + 5 test
5. Modul D: runbook (qwen32b/gptoss delegation, EN ~1000w)
6. Modul E: escrow setup script + 2 test
7. Modul F: MCP tool + count 110→111 + 3 test
8. Modul G: disaster scenarios + 4 test
9. Smoke 6 evidence
10. summary + completed/
11. memory snapshot 027
```

## 6. DoD Checklist

```
[ ] 7 modül A-G tamam
[ ] pytest 491 (+32)
[ ] tool 111
[ ] 6 smoke evidence
[ ] regression sıfır (010-026, özellikle 013 vault tests)
[ ] sops fail-fast prod mode test edildi
[ ] age rotation atomic rollback ispatlandı
[ ] HMAC chain tamper detection ispatlandı
[ ] 4 disaster senaryo runbook'ta + test edildi
[ ] summary + completed/
[ ] memory snapshot 027
```

## 7. Worker Notları

1. **sops binary mock** — testlerde subprocess.run mock; gerçek sops yüklü olabilir veya olmayabilir. `which sops` mock False → dev fallback path test.
2. **age key rotation atomic** — rotation iki dosyaya yazılır (eski + yeni); fail durumunda kayıp yok.
3. **HMAC secret** — `settings.vault_audit_hmac_secret` env (separate). Cron'la rotate edilebilir (28 günde bir, ileride).
4. **Recovery runbook EN** — komut blokları gerçek (Docker, sops, openssl), kullanıcı bunu canlı çalıştıracak.
5. **Escrow 1Password** — `op` CLI binary varsa kullan, yoksa S3 fallback. CLI yoksa hata YOK, kullanıcı 1 opsiyondan birini seçer.
6. **Disaster test mock** — `tempfile.mkdtemp()` ile izole vault, gerçek dosya silme/bozma simulate et.
7. **Backward compat:** mevcut 013 vault path'leri korunur. Yeni audit chain entry'leri eski log'a EK olarak yazılır.
8. **Performance:** audit chain 1000 entry verify <100ms (HMAC SHA256 hızlı).
9. **Memory snapshot:** task sonu yaz `session_resume_state_20260427_027.md`.
