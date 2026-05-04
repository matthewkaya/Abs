# Round 35 — Q12-L20-003 frontend fix (S5 R32 chaos finding closed)

**Sprint:** Q12 Session 6
**Layer:** L20 (chaos engineering) — UX fix
**Files touched:** 2 (1 src + 1 test)
**Status:** ✅ shipped — `test.fail()` → `test()` upgraded, 12/12 PASS across 4 browsers

---

## Real bug closed

### Q12-L20-003 (MED UX) — chat page hangs at "Yükleniyor…" under multi-503

Originally surfaced in Session 5 R32 via two `test.fail()` Playwright
scenarios. Root cause analysis in Session 6:

1. `useQuery` for `/v1/chat/sessions` defaulted to `retry: 3` with
   exponential backoff. Under cascade 503 the query stayed
   `isLoading=true` for ~15 s before reaching the error state.
2. Even after the error state was reached, no UI surface existed
   for the sessions-list error: `chat-error-tile` was conditionally
   rendered only inside the `messages.map` block (i.e. after the
   user successfully posted at least one message). On a cold-load
   503 with `messages.length === 0`, `EmptyState` rendered and no
   error indicator was visible.

## Fix surface

### `core/landing/app/panel/chat/ChatClient.tsx`

Two changes:

1. `sessionsQuery` now uses `retry: 1` instead of the default
   `retry: 3`. Under 5xx the error state lands in <2 s instead of
   ~15 s, matching the chat-completions retry policy in
   `lib/chat-stream.ts`.

2. New `sessions-error-tile` banner mounts above `<header>` whenever
   `sessionsQuery.isError`, regardless of `showEmpty` /
   `messages.length` state. Tile carries:
   - `role="alert"` (a11y + matches existing test selector)
   - `data-test="sessions-error-tile"`
   - Text: "Sohbet geçmişi yüklenemedi"
   - `Tekrar dene` button → `sessionsQuery.refetch()`

The tile is intentionally a separate surface from the
`chat-error-tile` (which still tracks chat-completion failures).
Both can coexist on a fully-degraded page.

### `core/landing/__tests__/playwright/q12-l20-chaos-multi.spec.ts`

`test.fail("scenario 6: …", …)` → `test("scenario 6: …", …)`.
Same for scenario 7. Doc comment rewritten to describe the fix
instead of the deferred finding.

---

## Verification

### Multi-failure chaos suite (the regression that drove the fix)

```bash
cd core/landing
npx playwright test __tests__/playwright/q12-l20-chaos-multi.spec.ts --workers=1
```

Result:

```
Running 12 tests using 1 worker
  ✓ chromium-desktop / scenario 6 (1.4s)
  ✓ chromium-desktop / scenario 7 (2.6s)
  ✓ chromium-desktop / scenario 8 (3.5s)
  ✓ chromium-mobile  / scenario 6 (1.5s)
  ✓ chromium-mobile  / scenario 7 (2.7s)
  ✓ chromium-mobile  / scenario 8 (3.6s)
  ✓ firefox-desktop  / scenario 6 (1.5s)
  ✓ firefox-desktop  / scenario 7 (2.4s)
  ✓ firefox-desktop  / scenario 8 (3.9s)
  ✓ webkit-desktop   / scenario 6 (1.9s)
  ✓ webkit-desktop   / scenario 7 (2.8s)
  ✓ webkit-desktop   / scenario 8 (4.0s)
  12 passed (34.3s)
```

All 4 browsers PASS scenarios 6, 7, 8. No `test.fail()` markers
remain in the file.

### Single-failure regression suite (no behavior drift on the
single-503 path)

```bash
npx playwright test __tests__/playwright/q12-l20-chaos.spec.ts \
  --project=chromium-desktop --workers=1
```

Result:

```
  ✓ scenario 1: backend 503 (1.5s)
  ✓ scenario 2: mid-stream abort (1.4s)
  ✓ scenario 3: 429 chain (1.4s)
  ✓ scenario 4: timeout (13.7s)
  ✓ scenario 5: 307 redirect loop (1.4s)
  5 passed (20.0s)
```

`chat-error-tile` still surfaces on chat-completion 503 (no drift on
existing behavior).

---

## Hygiene incident — stale dev `.next/` cache (not a code bug)

First test run failed with the page chunk
`/_next/static/chunks/app/panel/chat/page.js` returning **404**.
The dev server (PID 40516, started before the test session) was
serving HTML referencing chunks it had not compiled. Manual
investigation:

```bash
ls -la core/landing/.next/static/chunks/app/panel/chat/
total 0
drwxr-xr-x  2 …  64  May  3 21:45 .
drwxr-xr-x  2 …  64  May  3 21:45 ..
```

Empty directory while the served HTML referenced `page.js` inside
it. Cleared `.next/`, restarted `next dev --port 3457`, manually
warmed `/panel/chat` to trigger JIT compile, then re-ran tests —
all 12 PASS.

This is the same class of stale-cache bug T-Q02 reported (route
404 after T-061's `/pricing` route add). Filed as a hygiene note,
not a layered defect.

---

## Image rebuild

N/A — frontend-only change. Backend was not touched. The running
`infra-backend-1` image is unchanged from the last R29 rebuild
(2026-05-03T13:20:32Z).

---

## Layer matrix delta

| Layer | Before R35 | After R35 |
|-------|------------|-----------|
| L20 | 3/3 ⭐ deep (S5 R32 round 4 + 1 open MED bug) | **3/3 ⭐ deep CLOSED** (Q12-L20-003 fixed; no open layered bugs) |

L20 graduates from "deep with 1 deferred bug" to fully closed.

---

## Counters

- Backend pytest: unchanged (1630 PASS / 14 skipped) — no backend touched.
- Playwright: **+0 new tests**, **2 fixed `test.fail()` upgrades**, **0 regression**.
- Bugs fixed: **1** (Q12-L20-003 MED UX).
- Atomic commits in round: 1.
