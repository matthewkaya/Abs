# Round 80 — Q11-L13 fuzz weekend cron review + contract pin

**Date:** 2026-05-05 (Q12 Session 9)
**Branch:** `feat/sprint-q12-deep-quality`
**Layer:** Q12-L31 (NEW — fuzz cron stability contract)
**Commits:** 1 atomic (this round)

## Goal

Brief asks for a Q11-L13 fuzz cron weekend artifact review — read the
`.hypothesis/` artifact a Saturday run of `mutation-weekend.yml :: fuzz-30k`
would have uploaded, and ship a regression test for any counter-example.

## What we have access to

This worktree has no git remote configured (`git remote -v` empty), so we
can't `gh run list --workflow=mutation-weekend.yml` to fetch the actual
weekend artifact. The next-best signal:

- Local `.hypothesis/` holds only `constants/` and `unicode_data/`
  directories (Hypothesis cache). **No `examples/` directory exists** —
  Hypothesis only writes one when a test fails and the shrinker pins a
  minimum failing input. Empty examples = no historical counter-examples
  on this checkout.
- Re-running the full 30K fuzz suite locally is the cleanest substitute
  for "review the cron run":

```
$ HYPOTHESIS_PROFILE=ci pytest tests/test_q11_l13_hypothesis_10k.py -m fuzz
3 passed in 76.20s (chat + RAG + workflows × 10K each)
```

Both signals point to the same conclusion: **no counter-example to fix**.
The cron is healthy.

## What R80 actually ships

Since there's no counter-example to address, the round's value is in
**preventing the weekend cron from silently breaking**. A surprisingly
large class of failure mode is:

> "Someone reformats `mutation-weekend.yml`, drops the `fuzz-30k` job, or
> removes the `-m fuzz` selector — and the Saturday window quietly stops
> running for weeks before anyone notices the empty Monday review."

`test_q12_l31_fuzz_cron_contract.py` ships **5 pytest** that lock the
contract:

| Test | Asserts |
|------|---------|
| `test_workflow_file_exists_and_parses` | `mutation-weekend.yml` parses, `name == "Mutation Weekend"` |
| `test_saturday_cron_schedule_is_wired` | `0 2 * * SAT` cron is still in `on.schedule[]` (Saturday 02:00 UTC, off-hours) |
| `test_fuzz_30k_job_exists_with_correct_selector` | `jobs.fuzz-30k` exists, runs `pytest tests/test_q11_l13_hypothesis_10k.py -m fuzz` |
| `test_on_failure_artifact_upload_preserves_hypothesis_db` | the `if: failure()` upload step still uploads `core/backend/.hypothesis/` with retention ≥ 7 days |
| `test_fuzz_test_file_exists_and_has_fuzz_marker` | the pytest target file actually carries the `[fuzz]` marker — without it, `-m fuzz` would select 0 tests and silently pass |

The third + fifth tests together close the worst silent-failure mode:
even if both the cron job AND the marker existed, but were misaligned, the
Saturday run would pass with 0 tests selected. The combined assertions
make sure either side breaking trips the contract.

## YAML parsing gotcha (worth noting)

PyYAML reads the workflow's top-level `on:` key as Python boolean `True`
(YAML 1.1 truthiness rule). The cron-schedule test reads via
`workflow.get(True) or workflow.get("on")` so the test survives whichever
PyYAML version a future runner uses.

## Test results

```
tests/test_q12_l31_fuzz_cron_contract.py::test_workflow_file_exists_and_parses PASSED
tests/test_q12_l31_fuzz_cron_contract.py::test_saturday_cron_schedule_is_wired PASSED
tests/test_q12_l31_fuzz_cron_contract.py::test_fuzz_30k_job_exists_with_correct_selector PASSED
tests/test_q12_l31_fuzz_cron_contract.py::test_on_failure_artifact_upload_preserves_hypothesis_db PASSED
tests/test_q12_l31_fuzz_cron_contract.py::test_fuzz_test_file_exists_and_has_fuzz_marker PASSED
5 passed in 0.55s
```

Backend pytest delta: 1740 → **1745** (+5).
Local 30K Hypothesis fuzz: **3/3 PASS in 76.20 s, 0 counter-examples**.

## Image rebuild gate

Round adds new test file + reads existing workflow YAML; backend code
unchanged. Container exec gate not triggered.

## Followups (not this round)

- When the worktree gets a git remote wired, a thin S10 round can replace
  the local "30K passes here" check with `gh run list --workflow=
  mutation-weekend.yml --status=success --limit=4` to verify the last 4
  weekend windows all completed (no skipped or cancelled runs).
- Hypothesis stores `examples/` only on failure. A future helper that
  runs the fuzz with `--hypothesis-seed=<weekly-rotated-seed>` could
  catch a regression we'd otherwise miss until a different seed surfaced
  the same input — outside R80 scope.
