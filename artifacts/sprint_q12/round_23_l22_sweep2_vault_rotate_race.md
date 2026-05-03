# Round 23 — L22 sweep 2 vault rotate concurrent-race + audit + leak fix

**Sprint:** Q12 Session 3
**Layer:** L22 (race condition deep) — sweep 2
**Files touched:** 2 src + 1 new test
**Status:** ✅ shipped

---

## Real bugs surfaced

### Q12-L22-002 (HIGH data corruption / audit divergence) — Vault rotate has no concurrent guard

`POST /v1/admin/vault/rotate-key` was unguarded. Two admins (or admin
+ scheduled cron Sun 02:00 UTC) racing produced:

```
A: decrypt_all() with OLD key       -> snapshot1
B: decrypt_all() with OLD key       -> snapshot2 (independent copy)
A: shutil.move(tmp_key_A, key_path) -> key file = A
B: shutil.move(tmp_key_B, key_path) -> key file = B  (clobbers A)
A: encrypt_all(snapshot1)           -> uses key file = B (!)
B: encrypt_all(snapshot2)           -> uses key file = B
A: append_entry(new=A_fingerprint)  -> AUDIT CHAIN LIES
B: append_entry(new=B_fingerprint)
```

The worst part is the audit-chain divergence: ops cannot tell from
the audit log which key is actually on disk. Operator follows the
chain to "A is current" but disk holds B. Backup .bak files also race
(backup_A is overwritten by backup_B), so rollback is unreliable.

This is the same family as Q12-L22-001 (R15 setup wizard TOCTOU)
where two admin steps could overwrite each other's credentials. R23
ships the analogous `fcntl.LOCK_EX` cross-process guard.

**Fix:** new `_rotate_lock(blocking)` context manager opens
`<vault_key_path>.rotate.lock` and acquires `fcntl.LOCK_EX`. API path
calls non-blocking (returns 409 `rotation_in_progress`); cron path
can pass `blocking_lock=True` to queue. New
`RotationBusyError(RotationError)` lets the API distinguish 409
(busy) from 500 (genuine failure).

### Q12-L22-003 (MED info-leak — same Q12-L24 family)

Pre-fix, `RotationError` exception text was rendered into the
response body:

```py
except RotationError as exc:
    raise HTTPException(500, f"Rotation failed: {exc}") from exc
```

`exc.args[0]` for `_default_keygen` failures includes
`"age-keygen failed: <stderr>"` and `<stderr>` carries CLI internals
(file paths, env hints, sometimes stack traces depending on
sops/age version). For `decrypt_all` failures it carries
`"decrypt_all failed: <runner.VaultError text>"` which can include
sops parse errors, key fingerprints partial, etc.

**Fix:** keep response generic (`"rotation_failed"`, `"rotation_in_progress"`),
route `error_class=type(exc).__name__` to the audit channel only.
Same pattern as R14 Stripe str(exc) scrub and R22 Slack taxonomy
fix.

---

## Q12-L22-004 (LOW operability) — rotate denial paths silent in audit

Pre-Round 23 the rotate endpoint emitted no `abs.audit` event on
denial or even success. Vault rotate is one of the most
security-sensitive operations on the system; not having structured
audit on (denied/error/success/duration_ms/count) means ops cannot
graph rotation health, alert on a rotation-attempt spike, or
correlate a rotation to a downstream decrypt failure.

**Fix:** `admin.vault.rotate` now emits:
* `denied` (rotation_in_progress, 409)
* `error` (rotation_failed, 500, error_class=…)
* `success` (count=secrets_re_encrypted, duration_ms)

---

## Tests

`test_held_lock_makes_second_rotate_busy` — pre-acquires the lock on
a separate fd in the same process (fcntl is per-fd, so this is a
real contention demonstration without forking) and verifies the
second `rotate_age_key()` call raises `RotationBusyError`.

`test_lock_release_lets_next_rotation_succeed` — runs two sequential
rotations (A then B). The second's reported `new_fingerprint` is
recomputed from the actual on-disk key — proves the audit-vs-disk
divergence is no longer possible (post-fix: B's audit chain entry
matches B's actual key recipient).

`test_busy_response_emits_denied` — API smoke: hold the lock, hit
`POST /v1/admin/vault/rotate-key`, expect 409 +
`admin.vault.rotate denied reason=rotation_in_progress` audit.

`test_rotation_failure_emits_error_without_leaking_exc` — patches
`_default_keygen` to raise `RotationError("age-keygen failed: stderr
juice")`; asserts response body does NOT contain `"stderr juice"` and
audit `error_class=RotationError` is emitted.

`test_rotation_success_emits_success_with_count_and_duration` — happy
path emits `success` with `count=2` (foo + abs_stripe in fixture) and
`duration_ms` as a float.

---

## Image + container evidence

```
image_rebuilt_at: 2026-05-03T14:41:xx (Q12 Session 3 fourth rebuild)
container_pytest_pass: 14/14
container_emit_event_count: vault_admin.py:5 rotation.py:0 (lock only)
```

Live curl smoke (no auth → expect 401):
```
$ curl -sk -o /dev/null -w "%{http_code}\n" -X POST \
    -H 'Content-Type: application/json' -d '{"reason":"manual"}' \
    http://localhost:8000/v1/admin/vault/rotate-key
401
```

(Cannot test the 409-busy path live without an admin token + holding
the lock from a worker; the unit test is the load-bearing assertion.)

---

## L22 counter

* Sweep 1 (R15): setup wizard TOCTOU (Q12-L22-001 HIGH) — fcntl.LOCK_EX
  on `setup_state.json.lock`
* **Sweep 2 (R23): Vault rotate concurrent-race (Q12-L22-002 HIGH)
  + str(exc) leak (Q12-L22-003 MED) + audit silence (Q12-L22-004 LOW)
  — fcntl.LOCK_EX on `<vault_key_path>.rotate.lock`**

L22 → **2/3** (sweep 3 pending: OAuth client_id duplicate registration
race + Inngest worker idempotency double-fire dedup if applicable;
these need digging in `app/auth/oauth/server.py` and
`app/worker/inngest_app.py`).
