# Round 21 — L23 sweep 4 smart_link.py + beta_admin.py audit coverage

**Sprint:** Q12 Session 3
**Layer:** L23 sweep 4 part 2 of 2
**Files touched:** 2 src + 1 new test
**Status:** ✅ shipped

---

## R21 scope

### smart_link.py (7 raise sites covered)
* `_check_admin` 401 missing_bearer → `smart_link.admin.gate denied`
* `_check_admin` 403 admin_token_invalid → `smart_link.admin.gate denied`
* `github_callback` 400 state_invalid_or_expired → `smart_link.github.callback denied`
  (CSRF / replay / forged-state probe — most operationally important
  silent path on this module)
* `github_callback` happy-path → `smart_link.github.callback success`
* `github_callback` token-exchange-fail → `smart_link.github.callback failure`
* `github_refresh` 404 no_token_stored → `smart_link.github.refresh denied`
* `github_refresh` happy → `smart_link.github.refresh success`
* `github_revoke` happy → `smart_link.github.revoke success` (count=delete-flag)
* `store_api_key` 400 unsupported_provider → `smart_link.api_key.store denied`
* `store_api_key` 400 api_key_too_short → `smart_link.api_key.store denied`
* `store_api_key` 422 provider_validation_failed → `smart_link.api_key.store denied`
* `store_api_key` happy → `smart_link.api_key.store success` (duration_ms)

### beta_admin.py (7 raise sites + 2 success paths)
* `_require_admin` 401 missing_bearer → `admin.beta.gate denied`
* `_require_admin` 403 admin_token_invalid → `admin.beta.gate denied`
* `list_queue` 400 invalid_status_filter → `admin.beta.queue denied`
* `approve_request` 404 request_not_found → `admin.beta.approve denied`
* `approve_request` 409 request_already_rejected → `admin.beta.approve denied`
* `approve_request` happy → `admin.beta.approve success` (email_hint masked)
* `reject_request` 404 request_not_found → `admin.beta.reject denied`
* `reject_request` 409 request_already_approved → `admin.beta.reject denied`
* `reject_request` happy → `admin.beta.reject success` (email_hint masked)

---

## Real bug surfaced + fixed

`approve_request` and `reject_request` previously read
`row.email` *after* `db.commit()` for both `schedule_beta_sequence`
and `dw.notify_beta_approved`. Wiring the audit `email_hint=row.email`
into the same post-commit window made the bug deterministic:

```
sqlalchemy.orm.exc.DetachedInstanceError: Instance <BetaRequest at 0x...>
is not bound to a Session; attribute refresh operation cannot proceed
```

The pre-existing email_sequence + Discord callbacks were silently
swallowing this exception via their `try/except Exception as exc:
logger.warning(...)` blocks — meaning **beta-approval emails and
Discord notifications could fail in production any time the ORM
session expired between commit and post-commit work, with no signal
beyond a warning log line that nobody is paging on**.

Fix: capture `row_email = row.email` *before* `db.commit()` in both
handlers. All downstream callbacks (sequence + Discord + audit emit)
read the local string instead of the now-detached ORM attribute.

This is itself an L23 bug (silent failure mode) and was **only
surfaced by the audit coverage work** — the audit emit converted a
swallowed warning into a hard test failure.

---

## Image + container evidence

```
image_rebuilt_at: 2026-05-03T14:11:15Z (Q12 Session 3 second rebuild,
                  R20+R21 combined)
container_emit_event_count:
  setup.py:15  admin/auth.py:10  smart_link.py:13  beta_admin.py:10
container_pytest_pass: 28/28 (R21 sweep4 + smart_link_oauth_prod +
                       smart_link_api_key_prod + 031_beta_admin +
                       031_beta_portal)
```

Live container smoke:
```
$ curl -sk -o /dev/null -w "%{http_code}\n" \
    http://localhost:8000/v1/admin/beta/queue
401
$ curl -sk -o /dev/null -w "%{http_code}\n" \
    "http://localhost:8000/v1/smart-link/github/callback?code=x&state=forged-l23s4"
400
```

---

## L23 counter

* Sweep 1 (R13)        — auth.py 5 paths
* Sweep 2 (R18)        — me_account.py 11 paths
* Sweep 3 (R19)        — me_data_export.py 10 paths → **3/3 FULL CLEAN**
* Sweep 4 part 1 (R20) — setup.py + admin/auth.py = 23 paths
* **Sweep 4 part 2 (R21)** — **smart_link.py + beta_admin.py = 23 paths**

L23 → **4/3 deep** (Founder-verified silent-path inventory of 31 raise
sites is now 0; combined R20+R21 added 46 emit_event calls covering
denial + success sides).

---

## Sweep 4 close-out

| Module | Raise sites | Emits added | Status |
|--------|-------------|-------------|--------|
| setup.py | 8 | 13 | ✅ R20 |
| admin/auth.py | 9 | 10 | ✅ R20 |
| smart_link.py | 7 | 13 | ✅ R21 |
| beta_admin.py | 7 | 10 | ✅ R21 |
| **TOTAL** | **31** | **46** | **L23 4/3 deep** |
