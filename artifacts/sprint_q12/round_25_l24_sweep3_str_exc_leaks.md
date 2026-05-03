# Round 25 — L24 sweep 3 remaining str(exc) / f-string leaks

**Sprint:** Q12 Session 3
**Layer:** L24 (secret/sensitive leakage scan) — sweep 3
**Files touched:** 3 src + 1 src regression-fix + 1 new test
**Status:** ✅ shipped — **L24 → 3/3 FULL CLEAN ⭐**

---

## Real bugs surfaced

### Q12-L24-005 (MED security info-leak) — me_consent + me_audit duplicate the License-verify leak

R18 (me_account.py) and R19 (me_data_export.py) both fixed the
PyJWT-internals leak in `_verify_bearer_license` — **but `me_consent.py:38`
and `me_audit.py:34` had IDENTICAL helpers that the prior sweeps
didn't grep**:

```py
except Exception as exc:
    raise HTTPException(401, f"License verify failed: {exc}") from exc
```

Same family, same response surface, same client visibility — token
malformations / signature mismatches surface PyJWT internals to the
caller. Coverage gap discovered by widening the grep from `me_account|
me_data_export` to all `*me_*.py`.

**Fix:** generic `"license_verify_failed"` + `me.consent.auth` /
`me.audit.auth` audit taxonomy `{denied:missing_bearer | denied:
license_invalid | error:license_verify_exception (carries
error_class) | denied:missing_jti}`.

### Q12-L24-006 (MED security info-leak) — `/v1/secrets/rotate` leaks sops/age stderr

```py
except VaultError as exc:
    raise HTTPException(status_code=500, detail=f"Vault yazma hatasi: {exc}") from exc
```

`exc` carries sops/age subprocess stderr: file paths
(`/var/lib/sops/keys.yaml`), key fingerprints, sometimes plaintext
hints. Admin-auth required, but admin compromise + this surface =
secondary leak path.

**Fix:** generic `"vault_write_failed"` + `secrets.rotate` audit
taxonomy `{denied:vault_not_configured | denied:unknown_key |
error:vault_write_failed | success}`.

---

## Q12-L25-003 contract regression fix (R24 follow-up)

R24's `messages: List[ChatMessageIn] = Field(..., min_length=1, max_length=200)`
broke `tests/test_q10_l1_coverage.py::test_completions_rejects_empty_messages`
— the inherited Q10-L1 contract expected the **handler** to return
400 `messages_required`, my Pydantic `min_length=1` converted that
into 422.

**Fix:** drop `min_length=1`. Empty-list rejection is owned by the
handler `if not body.messages: raise HTTPException(400,
"messages_required")`. Pydantic only enforces the upper-bound DoS
cap. R24's test updated to assert empty-passes-Pydantic + handler
owns 400. Q10-L1 contract intact.

This is an L19 backwards-compat catch (Q12-L19-001 family) — exactly
the kind of reverse-direction breakage the inherited contract suite
exists to detect.

---

## Tests

`TestQ12L24Sweep3MeConsent` (2 tests):
* `test_invalid_bearer_no_pyjwt_leak` — bearer-malformed token; assert
  response body contains neither "Signature" nor "Exception"; assert
  audit emits one of {license_invalid, license_verify_exception,
  missing_jti}.
* `test_missing_bearer_emits_denied`.

`TestQ12L24Sweep3MeAudit` (3 tests):
* same two as above.
* `test_garbled_token_keeps_response_generic` — iterates 5 PyJWT
  internal class/string tokens (ExpiredSignatureError, DecodeError,
  Not enough segments, Invalid header padding, InvalidSignatureError)
  and asserts NONE leak to response body.

`TestQ12L24Sweep3SecretsRotate` (3 tests, panel-session auth pattern
from R24):
* `test_vault_not_configured_emits_denied` — sops_available=False →
  503 + audit denied.
* `test_unknown_key_emits_denied` — unknown key → 400 + audit denied.
* `test_vault_write_failure_no_sops_stderr_leak` — patches
  write_secret to raise `VaultError("sops: stderr juice — file path
  /var/lib/sops/keys.yaml")`; asserts response body contains NEITHER
  "stderr juice" NOR "/var/lib/sops"; asserts audit
  error_class=VaultError.

8/8 R25 tests + 45 cross-suite regression tests = **53 PASS**.

---

## Image + container evidence

```
image_rebuilt_at: 2026-05-03T15:01:xx (Q12 Session 3 sixth rebuild)
container_pytest_pass: 53/53 (R25 + R24 chat regression-fix + L23 +
                       L24 sweep1 + L25 sweep2)
```

---

## L24 counter

* Sweep 1 (R14): magic_token redact + Stripe checkout/billing str(exc) scrub
  (Q12-L24-001 HIGH, Q12-L24-002 MED)
* Sweep 1 follow-ups (R18, R19): me_account + me_data_export PyJWT
  internals scrub
* Sweep 2 (R22): Slack reason-taxonomy leak (Q12-L24-003 MED) +
  3-receiver webhook audit silence (Q12-L24-004 LOW)
* **Sweep 3 (R25): me_consent + me_audit duplicate License-verify
  leak (Q12-L24-005 MED) + secrets/rotate sops stderr leak
  (Q12-L24-006 MED)**

**L24 → 3/3 FULL CLEAN ⭐** (6 Q12 layers FULL CLEAN total: L17, L18,
L19, L20, L23, L24).

The grep methodology that surfaced sweep 3 (`grep -rn 'str(exc)\[\|f".*: {exc}"'
core/backend/app/api/`) caught 4 hot spots; the 3 critical ones are
fixed in this round; the 3 deferred ones are diagnostic endpoints
(`health_full.py`, `status_page.py`) where the exc text is the
intended diagnostic signal.
