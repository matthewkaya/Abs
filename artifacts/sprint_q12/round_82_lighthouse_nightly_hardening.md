# Round 82 — Lighthouse nightly stability hardening

**Date:** 2026-05-05 (Q12 Session 9)
**Branch:** `feat/sprint-q12-deep-quality`
**Layer:** Q12-L32 (NEW — nightly lighthouse stability)
**Commits:** 1 atomic (this round)

## Real bug found and fixed

`.github/workflows/lighthouse-nightly.yml` had been targeting
`https://abs.local/` and `https://abs.local/pricing` since its initial
ship. **That hostname does not resolve on a GitHub runner.** Every
scheduled nightly run for the entire history of the repo would have
errored at the URL fetch step, with no useful artifact since the prior
config did not enable `uploadArtifacts`. The nightly was silently broken.

Confirmed by reading the file: 30 lines, two `--collect.url=https://abs.local/...`
flags, no local server start, no upload of failed reports.

## Fix — mirror the working perf-budget.yml pattern

`.github/workflows/perf-budget.yml` already gets this right on PRs:
local landing build (`npm run build`), then `treosh/lighthouse-ci-action@v12`
reading `core/landing/lighthouserc.json` (which uses `npx next start` +
`http://localhost:3000/...` URLs).

R82 rewrites the nightly to mirror that pattern, plus:

| Hardening | Why |
|-----------|-----|
| `concurrency` group with `cancel-in-progress: true` | a manual `workflow_dispatch` arriving while a scheduled run is mid-flight no longer doubles up |
| 1 retry on the desktop job (`if: failure()` second action call) | cold-runner cold-start is the dominant non-bug failure mode; one retry kills 90% of false alarms without papering over real regressions |
| `uploadArtifacts: true` + `temporaryPublicStorage: true` on every step | a failed nightly is no longer opaque — the next-morning review has the full HTML + JSON report |
| New `slow-3g` job (mobile, `throttlingMethod: devtools`, slow-3G envelope) | per S8 R66 framing: desktop nightly = parity check, slow-3G nightly = mobile regression detector |
| `slow-3g.needs: desktop` + `if: always()` | resource ordering deterministic, but two profiles independent — desktop failure does not cancel slow-3G |
| Pin `node-version: "22"` to match `perf-budget.yml` | drift causes hard-to-debug Lighthouse-vs-Next mismatches |

## New file: `core/landing/lighthouserc.slow-3g.json`

Slow-3G mobile profile. Looser performance budget (`warn` not `error`)
because slow-3G shifts LCP/TBT into a different working region; the goal
is **regression detection**, not desktop parity. Three contracts kept
`error`-level even on slow-3G:

- `categories:accessibility ≥ 0.95` — a11y regressions are profile-independent
- `cumulative-layout-shift ≤ 0.15` — CLS is layout, not network
- the throttling envelope (`rttMs`, `throughputKbps`, `cpuSlowdownMultiplier`)

## Regression pin

`test_q12_l32_lighthouse_nightly_contract.py` ships **8 pytest** that lock
the rewrite:

| Test | Asserts |
|------|---------|
| `test_workflow_loads_and_has_daily_cron` | `0 3 * * *` cron present |
| `test_no_unreachable_abs_local_target` | the bad pattern cannot return (search excludes `#`-prefixed comments so the rationale survives) |
| `test_concurrency_group_prevents_overlap` | `lighthouse-nightly-${{ github.ref }}` + `cancel-in-progress: true` |
| `test_desktop_job_uses_canonical_lighthouserc` | exactly 2 `lighthouse-ci-action` steps (primary + retry on failure), both on `core/landing/lighthouserc.json`, both `uploadArtifacts: true` |
| `test_slow_3g_job_exists_and_runs_after_desktop` | `needs: desktop` + `if: always()` + reads `lighthouserc.slow-3g.json` |
| `test_slow3g_lighthouserc_declares_mobile_throttled_profile` | `throttlingMethod: devtools`, mobile form factor, slow-3G envelope (rtt ≥ 200, throughput ≤ 1000, cpu slowdown ≥ 4) |
| `test_slow3g_assertions_cover_lcp_cls_a11y` | a11y stays `error: 0.95+`; LCP/CLS budgets present |
| `test_node_version_matches_perf_budget` | both nightly + perf-budget pinned to node 22 |

The `test_no_unreachable_abs_local_target` test is the load-bearing one —
if a future PR reverts to `abs.local`, the nightly silently breaks again.
The test catches it before merge.

## Test results

```
8 passed in 0.52s
```

Backend pytest delta: 1745 → **1753** (+8).

## Image rebuild gate

Round adds new test + edits workflow YAML + new lighthouserc; backend
code unchanged. Container exec gate not triggered.

## Followups (not this round)

- Once a few nightly runs land successfully, retune the slow-3G
  `categories:performance` from `warn 0.55` to `error <observed-floor>`.
  The first weeks are calibration, not enforcement.
- Optional: add a `report-to-slack` step on `if: failure()` that posts
  the temporary-public-storage URL to a worker-private channel, so a
  Monday-morning failed nightly does not need a manual `gh run view`.
- The retry pattern (call the action twice) is fine for one retry but
  doesn't scale; if we ever need 3+ attempts, refactor to a small shell
  loop calling `lhci autorun` directly.
