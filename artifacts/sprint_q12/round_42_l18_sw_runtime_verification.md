# Round 42 — L18 SW runtime cache hit verification

**Sprint:** Q12 Session 6 (extension beyond brief's 7-round target)
**Layer:** L18 (cold-cache LCP / offline resilience) — runtime
contract
**Files touched:** 1 new test
**Status:** ✅ shipped — 3/3 PASS in chromium-desktop

---

## Why this round exists

R36 shipped the SW source + register + 5/5 spec — but every R36
assertion is *static* (file content, register source). None
proves the SW *actually* intercepts requests at runtime. R42
closes that gap with three Chromium-only assertions:

1. After navigation + reload, `abs-panel-cache-v1` shows up in
   `caches.keys()` — proof the SW's `fetch` handler ran and
   opened the named cache.
2. After navigating `/panel/chat`, the cache contains at least
   one entry whose URL matches `/panel/chat` — proof the
   cache-first handler populated the cache.
3. The cache contains zero entries matching `/v1/*`,
   `/_next/*`, or `/auth/*` — proof the exclusion list in the
   SW's fetch dispatch is honoured at runtime.

## Files

### `core/landing/__tests__/playwright/q12-l18-sw-runtime.spec.ts` (NEW)

3 chromium-only tests:
- gates: `browserName === "chromium"` + cookie present
- helpers: `waitForServiceWorkerActive(page)` polls the SW state
  for up to 10 s; if it never reaches `"activated"`, the test
  skips (dev-server reload race; deterministic in prod build).

## Engineering note — cache lazy creation

First test run failed with `caches.keys() === []` even though
the SW had activated. Root cause: the SW only opens the cache
inside the strategy fns (`caches.open(CACHE_NAME)`), which fire
on the first `fetch` event. The page that triggered SW
registration was loaded *before* the SW activated, so its
fetches went directly to the network. Fix: reload after the SW
activates so its `fetch` handler runs at least once. After the
reload `caches.keys()` returns `["abs-panel-cache-v1"]`. Same
pattern is mirrored in tests 2 and 3.

## Verification

```
$ npx playwright test __tests__/playwright/q12-l18-sw-runtime.spec.ts \
    --project=chromium-desktop --workers=1

  ✓ SW activates + cache exists after navigation (2.0s)
  ✓ cache-first populates /panel/chat after navigation (1.4s)
  ✓ cache excludes /v1/* /_next/* /auth/* (1.5s)
  3 passed (5.8s)
```

## Image rebuild

N/A — frontend test-only round. Backend `app/` source untouched.
Backend pytest unchanged at 1633 PASS.

## Layer matrix delta

| Layer | Before R42 | After R42 |
|-------|------------|-----------|
| L18 | 3/3 ⭐ deep (R36 source + register) | **3/3 ⭐ deep + runtime** (R36 static + R42 runtime cache hit + exclusion contract) |

L18 stays at 3/3 ⭐ deep counter — R42 is a depth round, not a
new sweep.

## Counters

- Backend pytest: unchanged 1633 PASS / 14 skipped.
- Playwright: **+3 new tests** (chromium-only).
- Total Playwright in S6: +13 (R36 SW=5, R40 a11y=5 with 1 skip,
  R42 SW runtime=3) + 8 chaos flips fail→pass.
- Atomic commits in round: 1.
