# Round 54 — Mutmut local actual run (Session 7)

**Sprint:** Q12 Session 7
**Layer:** L22 / L24 mutation-floor pinning
**Status:** SKIPPED — pending founder approval

---

## Why skipped

S7 brief explicit: founder approval required to launch a local
mutmut run on a critical module. Empirical S5 R31 measurement:
**16–24 minutes per pass** on `app/auth/oauth/server.py`. A full
3-module run (cascade + auth/oauth + api/auth) ≈ 1 hour of
non-parallelizable runtime that blocks every other test.

The S5 R31 pivot — focused boundary tests for high-yield
mutation classes — already covers the **known** survivors. The
weekend cron job shipped in S6 R41
(`.github/workflows/mutation-weekend.yml`) covers **unknown**
survivors at off-hours. There's no urgent reason to run mutmut
locally in this session; the local run remains a founder-gated
manual operation.

## How to invoke (when founder is ready)

```bash
cd core/backend
.venv/bin/mutmut run \
    --paths-to-mutate=app/auth/oauth/server.py \
    --tests-dir=tests/ \
    --runner='./.venv/bin/pytest -x'
.venv/bin/mutmut results > /tmp/mutmut-report.txt
```

Surviving mutants → boundary tests using the S5 R31
mutation-floor pinning template.

## Counters

- Backend pytest: unchanged 1665 PASS / 14 skipped.
- Atomic commits: 1 (this artifact).
