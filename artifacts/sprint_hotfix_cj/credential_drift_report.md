# Credential Drift Report — Sprint Hotfix CJ

**Run date:** 2026-04-29
**Trigger bug:** BUG-CJ-007 (setup wizard creds rejected by /auth/login)
**Status after fix:** ✅ PASS

## Test matrix

| Scenario | Endpoint | Expected | Actual | Verdict |
|----------|----------|----------|--------|---------|
| Setup wizard creds (admin@demo-acme.local / LocalPass2026!) | POST /auth/login | 200 + `source=setup_wizard` | 200 + `source=setup_wizard` | PASS |
| Bootstrap fallback (admin@local / CHANGEME) after `rm admin_credentials.json` | POST /auth/login | 200 + `source=bootstrap` | 200 + `source=bootstrap` | PASS |
| Wrong password against setup creds | POST /auth/login | 401 | 401 | PASS |
| Wrong email against setup creds | POST /auth/login | 401 | 401 | PASS |

## Implementation

`core/backend/app/api/auth.py` — `_load_admin_credentials()` is called on every
login attempt:

```python
def _load_admin_credentials() -> Tuple[str, bytes, str]:
    creds_file = Path(settings.data_dir) / "admin_credentials.json"
    try:
        raw = json.loads(creds_file.read_text(encoding="utf-8"))
        return raw["email"], raw["password_hash"].encode("utf-8"), "setup_wizard"
    except FileNotFoundError:
        pass
    except (KeyError, json.JSONDecodeError, OSError) as exc:
        logger.warning("admin_credentials.json unreadable: %s", exc)
    return ("admin@local",
            _hash_password(settings.admin_password_bootstrap),
            "bootstrap")
```

The previous regression (hard-coded `ADMIN_EMAIL = "admin@local"` + hash bound
at module import time) is now strictly fallback. `source` field in the login
response makes regressions visible in QA logs.

## Regression guard

A bash regression test is shipped in `repro.sh` — runs both paths on every
CI invocation. CRITICAL severity downgrade gate: if either path drops below
200 (or response misses the `source` field), the test exits non-zero.

## Open follow-ups

- Multi-admin support (DB-backed `users` table) deferred to Sprint 21.
- Magic-link claim flow (CJ-003 backend) writes to `tenants_pending.json`;
  promoting a pending entry to a real admin record is a separate sprint.
