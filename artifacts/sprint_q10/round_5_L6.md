# Q10 Round 5 — Layer L6 Security audit + OWASP top-10 review

**Tarih:** 2026-05-01
**Branch:** `feat/sprint-q10-quality-loop`

---

## Tarama özeti

### npm audit (frontend)

```
total = 7 (info=0 low=0 moderate=7 high=0 critical=0)

[moderate] @vitest/mocker · vite
[moderate] esbuild · website-can-read-dev-server (DEV ONLY)
[moderate] next · postcss
[moderate] postcss · XSS via Unescaped </style>
[moderate] vite · Path Traversal in optimised .map
[moderate] vite-node · vite
```

**Yorum:** Hepsi devDependency / build-tool zinciri. esbuild dev-server
zafiyeti yalnız `npm run dev` çalışırken; production build (`output: standalone`)
risk dışında. Sprint 060 nightly Trivy zaten bu chain için "no critical"
raporu üretiyor — Round 5 baseline ile uyumlu.

### Manual OWASP top-10 review (Q8 yeni endpoint'ler)

| OWASP # | Surface | Bulgu | Status |
|---------|---------|-------|--------|
| A01 Broken Access | `/v1/chat/sessions/{id}` | tenant_slug match check | ✅ |
| A01 | `/v1/mcp/tokens/verify` | bearer signature check | ✅ |
| A01 | `/v1/hooks/*` | bearer + scope match | ✅ |
| A03 Injection | `/v1/chat/completions` prompt | SQLModel ORM, parameterized | ✅ |
| A03 | XSS in markdown render | react-markdown auto-escape | ✅ |
| A05 Misconfiguration | `ABS_TEST_MODE=1` | not honoured in prod | ✅ (config gate) |
| A07 Auth Failure | panel session | bcrypt + JWT HS256 + same-site=strict cookie | ✅ |
| **A04 Insecure Design** | `/v1/hooks/quota-check` | **always returned `allow`** | **❌ Q10-L6-001** |
| A02 Crypto | mcp_tokens HMAC-SHA256 | session_secret yedekleme | ⚠ Q10-L6-002 (architectural) |
| A09 Logging | audit-log persist | CustomerAuditEntry append-only | ✅ |

---

## Bulgular

### Q10-L6-001 — claude_code_hooks/quota-check actual gate eksik

**Severity:** **HIGH** (security gate hiç işe yaramıyor)

**Kök neden:** `app/api/claude_code_hooks.py` ilk versiyonu hardcoded
`decision = "allow"` ile dönüyordu. Risky tool detection'u sadece reason
mesajına yazılıyordu, gerçek bir limit yoktu. Bu means runaway Claude
Code session'lar tek tenant'a sınırsız `Bash`/`Write`/`Edit` çağrısı
yapabilir, audit log dolar, kötü amaçlı kullanım kapısı açık kalır.

**Fix:** `RISKY_TOOLS = {"Bash","Write","Edit","NotebookEdit"}`,
`RISKY_HOURLY_LIMIT = 100`. Tenant başına `deque[float]` rolling-hour
sayacı + `threading.Lock`. Risky tool çağrıldığında:
1. cutoff = now - 3600s, eski kayıtları drop et
2. now timestamp'ini ekle, deque len kontrol et
3. limit aşıldıysa `permissionDecision: "deny"` + Türkçe uyarı

Production'da multi-replica için Redis swap yorumu eklendi (cluster-safe
rolling window).

**Test:** 3 yeni test `test_q10_l1_coverage.py`:
- `test_quota_check_allows_under_hourly_limit` (99 risky → all allow)
- `test_quota_check_denies_after_hourly_limit` (101 risky → deny + reason)
- `test_quota_check_non_risky_tool_unconditional_allow` (150 Read → allow)

**Doğrulama:**
```
$ pytest tests/test_q10_l1_coverage.py
18 passed, 1 warning in 8.01s
```
(15 önceki + 3 yeni Q10-L6-001 = 18 PASS)

### Q10-L6-002 — mcp_tokens revoke list yok

**Severity:** MED (operational risk, blackhole disclosure window)

**Kök neden:** Token leaked olduğunda revoke edebilmek için bir
blacklist tablosu / Redis denylist yok. Tek seçenek
`session_secret` rotate (tüm token'ları invalid eder).

**Status:** Audit-log finding olarak commit, fix Round 6+'da (Phase Q
backlog) — yeni `MintedTokenBlacklist` SQLModel + verify_token'da
lookup. Acil değil çünkü TTL 365d cap + scope ayrımı blast radius
kontrol altında.

### Q10-L6-003 — npm audit moderate × 7 (devDeps)

**Severity:** LOW

**Status:** Tracked. Production etkisi yok (next build standalone +
postcss prod chain'ini etkilemez). Sprint 060 nightly Trivy
re-confirms.

---

## L6 layer durumu — round 5 sonu

| OWASP/Audit hedefi | Round 5 status |
|--------------------|----------------|
| Q10-L6-001 quota-check actual gate | ✅ fix + 3 test PASS |
| Q10-L6-002 token revoke list | ⚠ backlog Phase Q |
| Q10-L6-003 npm audit moderate × 7 | ⚠ tracked, prod-safe |
| OWASP A01-A09 manual review | ✅ no high finding |
| Sprint 060 security-nightly.yml chain | ✅ no critical (baseline) |

L6 3-round-clean sayacı: **1/3** (1 HIGH bug fix + 2 architectural
backlog finding).

---

## Regression

- pytest `master_repro.sh phaseA` → 12/12 PASS
- `pytest tests/test_q10_l1_coverage.py` → **18/18 PASS** (Q10 L1+L6)
- vitest 22/22 PASS
- Q10 toplam backend test sayısı: 12 (Q8 chat) + 18 (Q10 L1/L6) = **30 PASS**

---

## Sonraki round

**Round 6 = L2 integration test** — cascade chain mock-mode roundtrip
(prompt → mock provider → SSE chunk → DB persist), RAG ingest+query
contract test, marketplace install→sandbox status poll.

---

**Round 5 status:** ✅ ship — 1 HIGH fix (Q10-L6-001), 2 architectural
finding tracked. L6 sayacı: 1/3.
