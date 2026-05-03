# Round 28 — L21 sweep 2 safe-expansion drills

**Sprint:** Q12 Session 4
**Layer:** L21 (fresh-deploy / safe drills) — sweep 2
**Files touched:** 1 new test (no src — non-destructive verification)
**Status:** ✅ shipped — **L21 → 2/3** (was 1/3 since Session 1 R12)

---

## What this round verifies

L21 was at 1/3 since Session 1's full alembic chain + 6-step wizard
E2E. The destructive drill (production-volume reset) is founder-gated.
This round expands the **non-destructive** envelope per Session 4
brief §3:

* alembic upgrade↔downgrade **10× idempotent**
* license JWT expiry **boundary edges** (now-1s, now+1s, now+24h, now+100y)
* license JWT **tampering** vectors (signature flip, payload mutation,
  rogue signing key, missing required claim, garbled token)

All eleven assertions are read-only against tempfile DBs and
in-memory keys; no production volumes touched.

---

## Test inventory

`core/backend/tests/test_q12_l21_safe_expansion.py` — 11 new tests.

| # | Vector | Q12 ID |
|---|--------|--------|
| 1 | alembic upgrade↔downgrade 10× idempotent (extends Q11-L14) | Q12-L21-002 |
| 2 | exp=now-1s → 401 expired | Q12-L21-003 |
| 3 | exp=now+1s → still valid this instant | Q12-L21-003 |
| 4 | exp=now+24h → unambiguously valid | Q12-L21-003 |
| 5 | exp=now+1s, sleep 2s → 401 (no skew leniency) | Q12-L21-003 |
| 6 | exp=now+100y → valid (no upper bound enforced — explicit non-bug) | Q12-L21-003 |
| 7 | signature byte flip → 401 InvalidSignature | Q12-L21-004 |
| 8 | payload byte flip (tier escalation) → 401 | Q12-L21-004 |
| 9 | missing `jti` (require-claim) → 4xx | Q12-L21-004 |
| 10 | garbled token → 4xx | Q12-L21-004 |
| 11 | rogue RSA signing key → 401 | Q12-L21-004 |

---

## Verification

```
host venv: 11/11 PASS in 3.20s
no backend source touched → image rebuild N/A (per CLAUDE.md
                            backend-only rebuild trigger)
```

The 10× alembic loop runs all eight migrations (0000_init_baseline
through 0008_minted_token_blacklist) downgrading and re-upgrading
each cycle, asserting set-equality of `inspect(engine).get_table_names()`
on every iteration. Catches: orphan-index leaks on downgrade,
constraint name collisions on re-upgrade, autoincrement counter drift.

The license-JWT boundary suite covers the four corners of RFC 7519
§4.1.4 + §4.1.6:
- exp ≤ now → reject
- exp > now → accept
- malformed / tampered → reject without internals leak
- key mismatch → reject

---

## Q12-L21-003 finding (LOW — documented non-bug)

The verifier accepts arbitrarily-distant `exp` values. A 100-year
license is valid. This is intentional for offline / air-gapped
deployments but pinned in this test as a regression guard so a future
"add max-license-life cap" decision is conscious, not silent.

---

## L21 counter

| Sweep | Round | Vector | Verdict |
|-------|-------|--------|---------|
| 1 | R12 (S1) | alembic 0000–0008 chain + head↔base + 6-step wizard E2E (3/3) | ✅ |
| 2 | **R28 (S4)** | **alembic 10× roundtrip + JWT boundary + tamper matrix (11/11)** | ✅ |
| 3 | (gated) | destructive production-volume drill — founder approval | 🔒 |

**Result: L21 → 2/3** (one slot intentionally founder-gated). 8 Q12
layers FULL CLEAN ⭐ unchanged (L17, L18, L19, L20, L22, L23, L24, L25).

---

## Delegation evidence

Self-write (test only — no domain logic; existing primitives
`verify_license`, `load_private_key`, `command.upgrade` all imported
unchanged).

---

## Next round

R29 = L26 sweep 2 (30dk Playwright headed Chromium + heap snapshot)
**OR** R30 = mutmut L1 mutation testing on `app/cascade/` +
`app/api/auth/` (founder priority dependent on remaining session
budget).
