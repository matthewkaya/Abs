# Q12 — Round 18 — L23 sweep 2 (me_account.py audit coverage)

**Tarih:** 2026-05-03
**Layer:** L23 — observability gap (sweep 2 — Q12 Session 2)
**Branch:** `feat/sprint-q12-deep-quality`
**Worker:** Opus 4.7 (1M ctx)

---

## 0. Hedef

Round 13'ün audit'i `core/backend/app/api/me_account.py` dosyasını
**top silent offender (11/11 raise)** olarak işaretledi. GDPR Article
17 (right to erasure) endpoint'lerinin failure path'leri:

| Senaryo | Endpoint | Status | Pre-fix audit |
|---------|----------|--------|---------------|
| Missing Bearer header | /v1/me/account/delete-{request,confirm,cancel} | 401 | ❌ silent |
| Malformed bearer license | aynı | 400/401 | ❌ silent |
| Missing JTI claim | aynı | 401 | ❌ silent |
| Expired delete token | /delete-confirm | 400 | ❌ silent |
| Invalid delete token signature | /delete-confirm | 400 | ❌ silent |
| Wrong scope (account.read) | /delete-confirm | 400 | ❌ silent |
| Missing sub | /delete-confirm | 400 | ❌ silent |
| JTI mismatch (cross-account delete) | /delete-confirm | 403 | ❌ silent |
| License row not found in DB | /delete-confirm, /delete-cancel | 404 | ❌ silent |
| Already purged | /delete-cancel | 410 | ❌ silent |

`log_customer_action` mevcuttu — ama yalnızca **success** path'lerinde
(account.delete_requested, scheduled, cancelled). Failure path'ler ops
incident response için ZORUNLU evidence trail yoktu.

Saldırı senaryosu: adversary leaked license token ile
`/delete-confirm` endpoint'ine başka kullanıcının jti'si ile delete-
token enjekte ederse, jti mismatch 403'e düşer ama hiçbir log yok →
ops dashboard'da "cross-account delete attempt" görünmez.

---

## 1. Fix (shipped) — emit_event tüm 11 path için

Helper'lar `_verify_bearer_license(authorization, request=None)` ve
`_verify_delete_token(token, request=None)` `Optional[Request]`
parametresi alacak şekilde güncellendi. emit_event çağrısı `request
is None` olduğunda da güvenli (audit.py None-safe).

| Yeni audit action | Reason'lar |
|-------------------|------------|
| `me.account.auth` | missing_bearer / license_invalid / license_verify_exception / missing_jti |
| `me.account.delete_token` | expired / invalid / wrong_scope / missing_sub |
| `me.account.delete_confirm` | token_jti_mismatch / license_not_found |
| `me.account.delete_cancel` | license_not_found / already_purged |

Outcome `denied` (intentional rejection) veya `error` (unexpected
exception). Reason taxonomisi sabit string set'i.

### Side fix — Q12-L24 follow-up (MED → fixed)

**Pre-fix:**
```python
raise HTTPException(401, f"License verify failed: {exc}") from exc
```

`str(exc)` PyJWT internal'larını yansıtıyordu (`InvalidSignatureError(...)`,
`InvalidAlgorithmError(...)`, `DecodeError("Not enough segments")`).
Adversary HTTP response body'sinden hangi PyJWT exception class'ının
raise olduğunu öğrenip auth bypass deneme stratejisini optimize
edebilir.

**Fix:**
```python
emit_event(request, action="me.account.auth", outcome="error",
           reason="license_verify_exception", error_class=type(exc).__name__)
raise HTTPException(401, "license_verify_failed") from exc
```

Exception class internal audit log'a düşer; client sadece generic
`"license_verify_failed"` görür.

---

## 2. Tests — `core/backend/tests/test_q12_l23_sweep2_me_account.py` (6 test)

```
TestQ12L23Sweep2MeAccountAuth (2):
  test_missing_bearer_emits_denied            ← 401 + reason="missing_bearer"
  test_invalid_bearer_emits_denied            ← 400/401 + audit + L24 leak guard

TestQ12L23Sweep2DeleteToken (3):
  test_expired_delete_token_emits_denied_expired   ← 400 + "expired"
  test_wrong_scope_delete_token_emits_denied_wrong_scope ← 400 + "wrong_scope"
  test_jti_mismatch_emits_denied               ← 403 + "token_jti_mismatch"

TestQ12L23Sweep2LicenseLookup (1):
  test_license_not_found_emits_denied          ← 404 + "license_not_found"
```

**Sonuç:** 6/6 PASS.

GDPR pre-existing tests (test_029_gdpr_account.py, 4 test) her ikisi
de hala PASS — backwards-compat preserved.

---

## 3. Layer state

| Layer | Counter | Notes |
|-------|---------|-------|
| **L17** | **3/3 ⭐** | bundle break-even validator + unit + CI gate |
| **L18** | **3/3 ⭐** | cold-cache + CDP throttle 12/12 PASS |
| **L19** | **3/3 ⭐** | backwards compat 11/11 + 1473 full suite PASS |
| **L20** | **3/3 ⭐** | chaos 5/5 PASS (redirect-loop fix) |
| **L21** | **1/3** | fresh-deploy drill (safe variant 3/3 PASS) |
| **L22** | **1/3** | race condition fix (setup wizard TOCTOU 4/4 PASS) |
| **L23** | **2/3** | observability sweep 2 (me_account.py 11 paths + 6/6 PASS) |
| **L24** | **1/3** + follow-up | secret leakage + me_account.py str(exc) fix |
| **L25** | **1/3** | boundary payload (marketplace + 14/14 PASS) |
| **L26** | **1/3** | JWT lifecycle hardening (typed exceptions + 9/9 PASS) |

**L23 sweep 2 → 2/3** progress (Round 19+ için 1 sweep daha gerekli
to FULL CLEAN).

---

## 4. Sıradaki target (Round 19+ rotation)

Aynı pattern ile patch edilebilecek silent offenders:
- me_data_export.py (10/10 silent — GDPR Article 20)
- setup.py (8/8 silent — installation auth)
- admin/auth.py (8/9 silent — admin login)
- smart_link.py (7/7 silent — third-party OAuth tokens)
- beta_admin.py (7/7 silent — beta gate)

---

## 5. Atomic commit

```
fix(q12/L23-sweep2): Round 18 me_account.py audit coverage — 11 paths emit_event + L24 str(exc) follow-up + 6/6 tests PASS
```
