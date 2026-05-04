# Round 41 — Mutmut weekend CI pattern

**Sprint:** Q12 Session 6
**Layer:** Q12-L22 (race condition deep) + L24 (secret leakage) — adjacent
**Files touched:** 2 new
**Status:** ✅ shipped — workflow + policy doc

---

## Brief

S5 R31 closing identified that full `mutmut` runs on a single
critical module (`app/auth/oauth/server.py`) cost 16–24 minutes,
which is incompatible with per-PR CI. The R31 pivot — focused
boundary tests — handles the *known* survivors. This round
covers the *unknown* survivors with a weekend cron job.

## Files

### `.github/workflows/mutation-weekend.yml` (NEW)

GitHub Actions workflow:
- Trigger: `schedule: cron 0 2 * * SAT` (Sat 02:00 UTC)
- Manual: `workflow_dispatch`
- Permissions: `contents: read` only
- Concurrency: cancel-in-progress per ref
- Timeout: 240 minutes (4h hard cap; current 3-module run ≈ 1h)
- Matrix:
  - `app/cascade` (router correctness, fallback chain integrity)
  - `app/auth/oauth` (token issuance / refresh / revocation)
  - `app/api/auth` (login + session cookie surface)
- Artifact: `mutmut-<module>` retained 30 days
- Summary: top 40 surviving mutants in `$GITHUB_STEP_SUMMARY`

Security:
- Matrix values are workflow-local strings (not user input)
- All `${{ }}` interpolations routed through `env:` blocks
  (defensive consistency with the security-reminder hook policy)
- No `github.event.*` interpolation in `run:` blocks

### `docs/security/mutation-weekend-policy.md` (NEW)

Policy doc covering:
- Why the cron job exists (16–24 min/module is too slow for PR CI)
- The three target modules and their security/correctness yield
- Triage flow (weekend run → Monday review → pin test or document
  equivalence)
- Pivoted vs blocking pattern (R31 + R41 are complementary, not
  redundant)
- Manual invocation: `gh workflow run mutation-weekend.yml`

## Verification

```
$ python3 -c "import yaml; yaml.safe_load(open('.github/workflows/mutation-weekend.yml'))"
YAML OK
```

YAML valid. Actual cron run is gated to next Saturday — the
workflow is shipped, the first run is empirical.

## Image rebuild

N/A — no backend `app/` source touched. CI/policy infrastructure
only.

## Counters

- Backend pytest: unchanged 1633 PASS / 14 skipped.
- New CI workflow: 1.
- New policy doc: 1.
- Atomic commits in round: 1.
