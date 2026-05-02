# Q12 — Round 14 — L24 secret/sensitive leakage scan

**Tarih:** 2026-05-03
**Layer:** L24 — secret/sensitive data leakage (Q12 Session 2 yeni)
**Branch:** `feat/sprint-q12-deep-quality`
**Worker:** Opus 4.7 (1M ctx)

---

## 0. Hedef

Brief: API key in error message? Password hash in response? JWT in URL
query? Vault secret in audit log? Bu KRİTİK — production'da müşteri
verisi sızdıracak path var mı? semgrep + manual response inspection +
log diff.

semgrep yerel kuruluda yok; manuel grep + live curl probe + AST
inspection ile aynı kapsam yapıldı.

---

## 1. Bulgular

### Q12-L24-001 — HIGH (security blocker)

**Lokasyon:** `core/backend/app/api/auth.py:428`

```python
# pre-fix
logger.info(
    "signup_pending email=%s slug=%s magic=/auth/magic?token=%s",
    body.email, body.tenant_slug, token,
)
```

**Risk:** `/auth/signup` endpoint magic_token'ı plaintext olarak
**application log'a yazıyor**. Token 24h geçerli ve `/auth/magic`
endpoint'inde tek atımda admin oturumu açıyor:

1. Log file'a read access olan herhangi biri (ops engineer, SRE,
   log aggregator vendor — Datadog/Logflare/Loki, accidental log
   dump in incident export, leaked backup) → token elde eder.
2. `GET /auth/magic?token=<leaked>` çağırır → admin session cookie
   alır.
3. Tenant'ın tüm panel + admin endpoint'lerine erişim.

**Live confirmation:**

```bash
$ curl -X POST http://localhost:8000/auth/signup \
    -H "Content-Type: application/json" \
    -d '{"email":"l24scan@test.local","tenant_slug":"l24scan","password":"TestPass2026!"}'
{"status":"pending","magic_link_sent":true,"tenant_slug":"l24scan",
 "magic_link":"/auth/magic?token=b-2NNKEaLN7uFUEd3cXYJB5CmElPvs78RoV3J7wRd4E"}
```

`docker logs infra-backend-1 | grep signup_pending` → tüm token'lar
plaintext. Backup volume veya logrotate arşivinde 90 gün+ tutulan
token'lar bile claim için yeterli (TTL 24h ama sıkışmış pending
hesaplara karşı log'dan replay edilebilir).

**Fix (shipped):**

```python
logger.info(
    "signup_pending email=%s slug=%s token_hint=%s***",
    body.email, body.tenant_slug, token[:6],
)
```

`token_hint` (6 char) ops correlation için yeterli; full token claim
için yetersiz. Response body değişmiyor — self-host SMTP-less
installation için magic_link API yanıtında dönmeye devam etmek
zorunda (caller == admin == self).

### Q12-L24-002 — MED (defense-in-depth)

**Lokasyonlar:**
- `core/backend/app/api/checkout.py:91` — `f"Stripe error: {msg}"` where
  `msg = getattr(exc, "user_message", None) or str(exc)`
- `core/backend/app/api/billing_portal.py:75` —
  `detail=t(..., detail=str(exc)[:200])`

**Risk:** Stripe error string'leri internal account ID'leri (`cus_*`,
`sub_*`, `acct_*`, theoretical `sk_live_*` prefix), validation iç
mesajları içerebilir. Adversary bu ID'leri:
- Customer enumeration için fingerprint olarak kullanabilir.
- Stripe Dashboard'a brute-force search ile başvurabilir
  (Stripe API doesn't allow this, ama internal tooling olabilir).
- Account-internal endpoint structure'ı yansıtabilir.

**Fix (shipped):**

İki dosyada da `str(exc)` fallback'ı kaldırıldı; sadece Stripe'ın
kendi `user_message` field'ı (zaten son-kullanıcıya gösterilmek üzere
sanitize edilmiş) veya generic `"stripe_unavailable"` döndürülüyor.
Full exception `logger.exception` ile internal log'a gidiyor.

---

## 2. Tarama kapsamı (NEGATIVE findings — sızıntı yok)

Aşağıdaki vektörler tarandı; **leak bulunmadı** (regression guard'a
gerek yok ama dokümante ediyoruz):

| Vektör | Komut | Sonuç |
|--------|-------|-------|
| `print(...)` ile secret yayılımı | `grep -rn print( | grep token\|password\|secret` | 0 hit |
| `detail=` içinde password/hash | `grep detail= | grep password\|hash\|secret` | 0 hit |
| `mcp_tokens.py` log line'larında JWT | manual read | sadece `tenant`, `scope`, `label`, `expires_at` — token YOK |
| `vault_secrets.py` rotate/encrypt log'da plaintext | manual read | sadece `key_name`, `provider`, `len(value)` — değer YOK |
| `gmail_mcp.py` token store log | manual read | sadece `tenant_id`, `scope` — token YOK |
| `auth/oauth/server.py` JWT log | grep | sadece `cerbos_decision_failed status=%s` |
| Response body password_hash leak | `grep return.*password_hash` | 0 hit |
| Stack trace to client | `grep traceback\|str(exc)\|repr(exc)` | yalnız 2 Stripe hit yukarıda |

---

## 3. Shipped — `core/backend/tests/test_q12_l24_secret_leakage.py` (5 test)

```
TestQ12L24SignupTokenNotLogged:
  test_full_magic_token_absent_from_log     ← log line'da full token YOK
  test_log_carries_token_hint_for_correlation ← `token_hint=XXX***` var
  test_response_body_still_returns_magic_link ← self-host contract korundu

TestQ12L24StripeDetailScrub:
  test_billing_portal_stripe_error_detail_safe ← cus_*/sub_*/acct_*/sk_live_* leak guard
  test_checkout_stripe_error_detail_safe       ← same regex guard
```

`_STRIPE_INTERNAL_ID_PATTERN = r"\b(cus_[a-zA-Z0-9]+|sub_[a-zA-Z0-9]+|acct_[a-zA-Z0-9]+|sk_live_[a-zA-Z0-9]+)\b"` — adversary
Stripe API key prefix dahil olmak üzere 4 ID class taraması.

**Sonuç: 5 passed in 2.45s.** Full backend regression: pending
verification.

---

## 4. Layer state

| Layer | Counter | Notes |
|-------|---------|-------|
| **L17** | **3/3 ⭐** | bundle break-even validator + unit + CI gate |
| **L18** | **3/3 ⭐** | cold-cache + CDP throttle 12/12 PASS |
| **L19** | **3/3 ⭐** | backwards compat 11/11 + 1473 full suite PASS |
| **L20** | **3/3 ⭐** | chaos 5/5 PASS (redirect-loop fix) |
| **L21** | **1/3** | fresh-deploy drill (safe variant 3/3 PASS) |
| **L22** | **0/3** | pending Round 15 |
| **L23** | **1/3** | observability fix (req_id + emit_event + auth.py 9/9 PASS) |
| **L24** | **1/3** | secret leakage fix (magic_token log + Stripe str(exc) — 5/5 PASS) |
| **L25** | **0/3** | pending Round 17 |
| **L26** | **0/3** | pending Round 16 |

---

## 5. Atomic commit

```
fix(q12/L24): Round 14 magic_token log redaction (HIGH) + Stripe str(exc) scrub (MED) — 5/5 tests PASS
```
