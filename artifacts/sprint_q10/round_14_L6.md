# Q10 Round 14 — Layer L6 security re-scan + backlog execute

**Tarih:** 2026-05-01
**Branch:** `feat/sprint-q10-quality-loop`
**Commit:** `1212862`

---

## Hedef

Round 5'te tracked olan iki backlog finding'i execute et:

| ID | Severity | Açıklama |
|----|----------|----------|
| Q10-L6-002 | MED | mcp_tokens revoke list endpoint yok |
| Q10-L6-003 | LOW | npm audit moderate × 7 dep upgrade |

---

## Q10-L6-002 — Token revocation (MED → fix)

### Yeni model

`MintedTokenBlacklist` (SQLModel, table=True):

| Column | Tip | Not |
|--------|-----|-----|
| id | int PK | auto |
| token_digest | str(64) unique | sha256(token) hex — raw token DB'ye yazılmaz |
| tenant_slug | str(64) index | tenant-scoped lookup |
| label | str(64) | mint-time label kopyası |
| revoked_by | str(254) | admin email (audit) |
| revoked_at | datetime | default now UTC |
| expires_at | datetime? | original token exp (post-exp GC için) |
| reason | str(256)? | optional admin not |

### Yeni endpoint'ler

- `POST /v1/mcp/tokens/revoke` — admin-only (`current_admin` dep), idempotent.
  Token malformed/expired bile blacklist'e eklenir → leaked digest audit log.
- `GET /v1/mcp/tokens/revoked` — admin'in tenant'ı için liste, `revoked_at desc`.

### verify_token() değişikliği

HMAC + exp check'lerinin sonuna `_is_revoked(token)` lookup eklendi.
Revoked token: `401 detail="token_revoked"`.

### Test (4 yeni)

`test_q10_l1_coverage.py::TestMcpTokenRevoke`:
- `test_revoked_token_fails_verify_with_token_revoked_detail`
- `test_revoke_is_idempotent`
- `test_revoked_list_includes_label_reason_and_actor` (digest 64-char,
  `abs_mcp_` prefix yok)
- `test_other_tenant_token_not_listed`

```
$ pytest tests/test_q10_l1_coverage.py
22 passed (18 → 22, +4 yeni)
```

### OWASP gözden geçirme

| OWASP | Bulgu |
|-------|-------|
| A01 Broken Access | revoke + revoked endpoint admin-required (`current_admin`); tenant filter `_resolve_tenant(admin["sub"])` |
| A07 Auth | digest-only persistence — DB leak ≠ live-token disclose |
| A09 Logging | `logger.info` revoke event (tenant + label + actor + reason); `CustomerAuditEntry` zinciri devam |

---

## Q10-L6-003 — npm audit moderate (LOW → 5/7 fix)

### Tarama

`npm audit --json` (frontend `core/landing`):

**Önce:** `info=0 low=0 moderate=7 high=0 critical=0`

**Şimdi:** `info=0 low=0 moderate=2 high=0 critical=0`

### Upgrade

| Paket | Önceki | Yeni |
|-------|--------|------|
| vitest | ^2.1.8 | ^3.2.4 |
| @vitest/coverage-v8 | ^2.1.8 | ^3.2.4 |
| @vitest/mocker, esbuild, vite, vite-node | (transitive) | vitest 3 chain |

`--legacy-peer-deps` kullanıldı (react@19 vs tremor@18 peer mismatch
proje baseline'ından geliyor, Round 14 tarafından eklenmedi).

### Vitest 4 attempt + revert

Vitest 4 (rolldown JSX parser default) denendi: 21 test file'ın
17'si parse-fail (`Cannot parse Hero.test.tsx`, `Failed to parse source
for import analysis...jsx=preserve`). Tsconfig migration gerekiyor —
bu round scope dışı, vitest 3.x'te sabitlendi.

### Kalan 2 moderate

`next` + `postcss` — npm audit'in önerdiği "fix" Next 15 → 9.3.3 downgrade
(production-broken). Ignored, Sprint 060 nightly Trivy zaten "no critical"
raporlamaya devam edecek.

### Regression baseline

| Vitest | Files (failed/passed) | Tests (failed/passed) |
|--------|------------------------|------------------------|
| 2.1.8 öncesi | 9 / 12 | 25 / 65 |
| 3.2.4 sonrası | 9 / 12 | 25 / 65 |

%100 paritedir — vitest 3 upgrade hiç yeni test bozmadı. Mevcut 25
fail önceden var olan UI copy drift (Pricing TR copy değişmiş, ManageModal
button naming, vb.) — bu Q10 scope'u dışında, ayrı sprint.

---

## L6 layer durumu

| Audit hedefi | Round 14 sonu |
|--------------|---------------|
| Q10-L6-001 quota-check actual gate | ✅ (Round 5) |
| Q10-L6-002 token revoke list | ✅ (bu round) |
| Q10-L6-003 npm audit moderate × 7 | ✅ 5/7 fix, 2 ignored (downgrade önerisi) |
| OWASP A01-A09 manual review | ✅ no high finding |
| Sprint 060 security-nightly.yml | ✅ no critical (baseline) |

L6 3-round-clean sayacı: **1/3 → 2/3**.

---

## Atomic commit

`1212862` — fix(q10/L6): Round 14 — Q10-L6-002 token revoke + L6-003 vitest upgrade

---

## Sonraki round

**Round 15 = L7 visual regression baseline run.**

`q10-visual.spec.ts` (Round 9 ship) `--update-snapshots` ile ilk run,
ardından 2. run'da diff bul + atomic fix per visual delta.

---

**Round 14 status:** ✅ ship — Q10-L6-002 fix + 4 test, Q10-L6-003 5/7
fix, 0 regression. L6 sayacı 1/3 → 2/3.
