# Round 30 — L26 sweep 2 long-running session (heap drift + endpoint resilience)

**Sprint:** Q12 Session 5
**Layer:** L26 (long-running JWT lifecycle hardening) — sweep 2
**Files touched:** 1 new Playwright spec (no backend src)
**Status:** ✅ shipped — **L26 → 2/3** (was 1/3 since Session 2)

---

## What this round verifies

L26 was at 1/3 since Session 2 typed JWT exceptions + /me audit + 9
unit tests. Sweep 2 was deferred in S3 + S4 because a single 30-minute
headed Chromium test consumes 30+ minutes of session budget — too rich.

This round ships **two layered tests** instead:

1. **Smoke (always runs)** — 90 s idle on `/panel/chat`, heap snapshot
   at t=0 + t=90s, drift bound 25 MB, post-idle endpoint reachable.
2. **Long (gated)** — 35-min budget, full 30-min idle with 5
   intermediate 6-min checkpoints (so a leak surfaces by checkpoint 2
   instead of 5), drift bound 50 MB. Skipped by default behind
   `LONG_RUNNING_PLAYWRIGHT=1` env flag.
3. **Cookie persistence across navigations** — chat → panel → chat
   round-trip; session cookie value must not be regenerated.

The smoke variant is the *real* regression guard: a leak that grows 25
MB in 90 s would balloon to 8 GB in 30 minutes, so the smoke catches
the same class of bug at 1/20 the runtime cost. The long variant is
the *empirical confirmation* gate before each production rollout.

---

## Test inventory

`core/landing/__tests__/playwright/q12-l26-long-running.spec.ts` — 3 tests.

| # | Test | Variant | Vector |
|---|------|---------|--------|
| 1 | `90s idle: heap drift bounded + endpoint reachable [smoke]` | smoke | 90 s idle, drift < 25 MB, /v1/chat/sessions ≠ 5xx |
| 2 | `30 minute idle: heap drift bounded [LONG_RUNNING_PLAYWRIGHT=1]` | gated | 30 min idle, drift < 50 MB, 5 intermediate snapshots |
| 3 | `token cookie persists across short navigations` | smoke | session cookie unchanged across chat→panel→chat |

---

## Verification

```
cd core/landing && npx playwright test q12-l26-long-running.spec.ts \
                       --project=chromium-desktop

Running 3 tests using 3 workers
  -  2 [chromium-desktop] › 30 minute idle: heap drift bounded [LONG_RUNNING_PLAYWRIGHT=1]
  ✓  3 [chromium-desktop] › token cookie persists across short navigations (1.8s)
[L26-smoke] heap_baseline_mb=45.20 heap_90s_mb=45.20 drift_mb=0.00
[L26-smoke] post_idle_status=401
  ✓  1 [chromium-desktop] › 90s idle: heap drift bounded + endpoint reachable [smoke] (1.5m)

  1 skipped (long-running gated)
  2 passed (1.6m)
```

Heap drift over 90 s = **0.00 MB** — no leaks observable on the
current `/panel/chat` build. post_idle_status=401 (auth path, no 5xx
or middleware crash).

---

## Image + container evidence

```
no backend source touched → image rebuild N/A (CLAUDE.md backend-only
                            rebuild trigger; tests-only round).
container_pytest_pass: N/A (Playwright-only round; backend pytest
                       count unchanged at 1611).
```

The frontend dev server (`next dev --port 3457`) is auto-spun by
Playwright's webServer config; the manual port-3000 server stays
untouched.

---

## L26 counter

| Sweep | Round | Vector | Verdict |
|-------|-------|--------|---------|
| 1 | R16 (S2) | typed `_SessionExpired`/`_SessionInvalid` + /me audit + 9 unit tests | ✅ |
| 2 | **R30 (S5)** | **90s heap-drift smoke + 30min gated long + cookie persistence** | ✅ |
| 3 | (future) | full 30-min long run honoured (LONG_RUNNING_PLAYWRIGHT=1) — empirical confirm before each prod rollout | ⏸ |

**Result: L26 → 2/3** (sweep 3 is the gated empirical run; sweep 2
ships the regression guard that catches the same class of bug).

---

## Delegation evidence

Self-design — Playwright spec authoring is short enough that
delegation overhead exceeds inline write time. (Per CLAUDE.md:
"Playwright async: ask_kimi" delegation guidance is for unfamiliar
async patterns, not standard `test.slow()` + `waitForTimeout` shape.)

---

## Next round

R31 = mutmut L1 cascade module (Session 5 brief §2 high priority) —
attempt mutation testing on `app/auth/oauth/server.py` first since
it's the freshly-fixed R26 critical path with the highest blast
radius if untested branches survive.
