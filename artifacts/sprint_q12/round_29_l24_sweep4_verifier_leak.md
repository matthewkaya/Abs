# Round 29 — L24 sweep 4 verifier.py PyJWTError leak (last sibling)

**Sprint:** Q12 Session 4
**Layer:** L24 (secret/sensitive leakage scan) — sweep 4 (deep)
**Files touched:** 1 src + 1 new test
**Status:** ✅ shipped — **L24 → 4/3 deep** (defense-in-depth, all known leaks closed)

---

## Real bug surfaced

### Q12-L24-007 (LOW security info-leak) — PyJWTError catch-all branch in `verifier.py`

`app/licensing/verifier.py:51` (pre-fix):
```py
except PyJWTError as exc:
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail=f"License verification error: {exc}",
    ) from exc
```

This is the catch-all parent class branch for any `PyJWTError`
subclass that escapes the more specific catches above
(`ExpiredSignatureError`, `InvalidSignatureError`, `InvalidTokenError`).
The f-string interpolates the raw exception message, which can include
PyJWT-internal state (constraint names, decoder phase, key id hashes
when keysets are misconfigured).

**Why prior sweeps missed it:**
- R14 fixed admin/api leaks (`me_account.py`, signup magic_token).
- R18/R19 fixed `me_data_export` and re-grep'd `me_*` modules.
- R22 fixed webhook signature reason taxonomy.
- R25 swept `me_consent`, `me_audit`, `secrets/rotate`.
- All of those grep'd `app/api/**` and `app/me_*`. The `verifier.py`
  is in `app/licensing/` and was outside those globs.

**Why it matters:**
- The PyJWTError parent rarely fires today (subclasses cover the
  current PyJWT release). But it is a **passive-vulnerability**: any
  future PyJWT release that adds a new error subclass would silently
  fall through to the leak path.

---

## Fix shipped

`core/backend/app/licensing/verifier.py`:

```py
except PyJWTError as exc:
    logger.warning(
        "license_verify_pyjwt_error error_class=%s",
        type(exc).__name__,
    )
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="license_verify_failed",
    ) from exc
```

- Generic stable detail string.
- `error_class` taxonomy in ops audit (warning level), no raw message.
- Module-level logger added (mirrors `me_consent.py` / `me_audit.py`
  pattern from R25).

---

## Test inventory

`core/backend/tests/test_q12_l24_verifier_pyjwt_leak.py` — 2 new tests.

| # | Test | Vector |
|---|------|--------|
| 1 | `test_q12_l24_007_pyjwt_error_response_is_generic` | mock raises FakeWeirdPyJWTError("INTERNAL: secret_key=hunter2"); assert detail = `license_verify_failed`, no leakage; assert ops warning carries `error_class` only |
| 2 | `test_q12_l24_007_existing_specific_branches_still_specific` | Regression: Expired → 401 "expired"; garbled → 400 (format/license_verify_failed) — sweep didn't over-generalise |

---

## Verification

```
host venv: 2/2 PASS in 0.39s (subset)
sibling regression (Q12-L24 + L21 + L22 + L25 + oauth + marketplace + rag):
  43 passed, 1 skipped in 15.26s
```

---

## Image + container evidence

```
image_rebuilt_at: 2026-05-03T13:20:32Z (Q12 Session 4 third rebuild)
container_grep_count: /app/app/licensing/verifier.py: 2
  (license_verify_failed + license_verify_pyjwt_error)
```

---

## L24 counter

| Sweep | Round | Vector | Verdict |
|-------|-------|--------|---------|
| 1 | R14 (S1) | magic_token signup leak + Stripe str(exc) | ✅ |
| 2 | R22 (S3) | webhook signature taxonomy leak (Slack/GitHub/Stripe) | ✅ |
| 3 | R25 (S3) | me_consent + me_audit + secrets/rotate | ✅ ⭐ FULL CLEAN |
| **4** | **R29 (S4)** | **verifier.py PyJWTError catch-all str(exc)** | ✅ deep |

**Result: L24 → 4/3 deep** (defense-in-depth; one leak closed beyond
FULL CLEAN threshold). 8 Q12 layers FULL CLEAN ⭐ unchanged
(L17, L18, L19, L20, L22, L23, L24, L25).

---

## Delegation evidence

Self-write (single-line fix; test mocks PyJWTError subclass to force
the catch-all path).

---

## Next round

R30 = mutmut L1 mutation testing on `app/cascade/` + `app/api/auth/`
(Session 4 brief §2 medium priority) — context permitting.
