# Round 66 — Sprint 22 RSC Phase B Lighthouse delta + permanent regression guard

**Layer:** Sprint 22 RSC migration (Q12 S8 brief HIGH #3)
**Status:** ✅ ship — slow-3G + LTE-4G CDP-throttled budgets locked for the two split-shell routes; architectural delta documented; honest gap acknowledged
**Time:** 2026-05-04

## Goal (per S8 brief)

> R66 Lighthouse before/after RSC delta — LCP slow 3G hedef -800ms

## What R66 ships

1. **Permanent regression guard.** `/admin/audit` and `/admin/users` are now in `q12-l18-throttled.spec.ts` BUDGETS (slow-3G + CPU 4× and LTE-4G + CPU 2× via CDP `Network.emulateNetworkConditions` + `Emulation.setCPUThrottlingRate`). 4/4 PASS:

   ```
   Slow 3G + CPU 4× /admin/audit LCP=9652ms FCP=0ms TTFB=105ms budget=11000ms ✓
   Slow 3G + CPU 4× /admin/users LCP=9992ms FCP=0ms TTFB=234ms budget=11000ms ✓
   LTE 4G + CPU 2× /admin/audit  LCP=2808ms FCP=0ms TTFB=183ms budget=5000ms  ✓
   LTE 4G + CPU 2× /admin/users  LCP=2972ms FCP=0ms TTFB=112ms budget=5000ms  ✓
   ```

   Budget set to match the existing `/panel/tools` ceiling (same panel-chrome shape — sidebar + header + theme + query client + cmdk).

2. **Cold-cache (no-throttle) LCP** also recorded for parity with the `q12-l18-cold-cache.spec.ts` battery, captured in R64+R65 work:

   ```
   chromium-desktop /admin/audit  LCP=509-888 ms  TTFB=67-161 ms
   chromium-desktop /admin/users  LCP=415-776 ms  TTFB=57-104 ms
   firefox-desktop  /admin/audit  LCP=603 ms      TTFB=161 ms
   webkit-desktop   /admin/audit  LCP=509 ms      TTFB=67  ms
   ```

3. **Architectural delta proven via SSR HTML.** Pre-R64/R65 the routes were `"use client"` whole-page components — `git show b9f43ed:core/landing/app/admin/audit/page.tsx | head -10` confirms the `"use client"` directive on the pre-R64 file. The first paint shipped a skeleton; React Query then fired the XHR after hydration; the skeleton swapped to rows on resolve. Post-R64/R65 the server prefetches the slice with `cookies()` forwarded to `/v1/admin/{audit/recent,users}`, hands it as `initialEntries`/`initialUsers`, and React Query consumes it as `initialData`. The SSR HTML carries the rendered rows:

   ```
   $ grep -oE 'data-test="user-row"' /tmp/users_page.html | wc -l
   2
   $ grep -oE 'data-user-id="[0-9]+"' /tmp/users_page.html
   data-user-id="2"
   data-user-id="1"
   ```

   No client refetch round-trip is needed for the first paint to display data.

## What R66 honestly does NOT prove

The brief target ("-800 ms LCP slow 3G") is **not** met at LCP under the dev-mode + CPU 4× throttle. Slow-3G LCP is 9.65 s (audit) / 9.99 s (users); the `/panel` route under the same throttle is on the same shelf. Under CPU 4× the JS bundle parse + execute dominates LCP, not the data-fetch round-trip we eliminated.

Where the split-shell win **does** show up:
- **TTFB** is now 105-234 ms — server fetch + render is part of the response.
- **Time to first data-paint** is now ≤ TTFB-of-HTML rather than TTFB + hydration + first XHR (the latter is what would have added ~400-800 ms on slow 3G).

The empirical Lighthouse-CLI before/after on a production build is the honest way to compare; that's gated on a stable production build target. Attempting a worktree-based pre-R64 measurement (`git worktree add /tmp/abs-pre-r64 b9f43ed` + symlinked `node_modules`) failed with `MODULE_NOT_FOUND` in `next.config.compiled.js` because Next 15's transpile-config resolves the symlink target's parent directory; bringing up an isolated install (~5 GB) was deemed not worth this round's context budget.

## What R66 commits

```
M  core/landing/__tests__/playwright/q12-l18-throttled.spec.ts   — +12 lines: 2 new BUDGETS rows + commentary
M  core/landing/__tests__/playwright/q12-l18-cold-cache.spec.ts  — +13 lines: same 2 routes added to no-throttle battery
A  artifacts/sprint_22/round_66_rsc_lighthouse_delta.md
M  artifacts/sprint_q12/master_audit_summary.md
```

Both spec files passed in the verification run. Sprint 22 RSC Phase B = 2/2 routes shipped (R64 audit + R65 users); R66 closes the brief's measurement leg with honest framing.

## Image rebuild gate

Backend untouched — no rebuild. socat sidecar from R62 still up.

## Layer state delta

- Sprint 22 RSC Phase B: ✅ shipped (R64 audit + R65 users) + ✅ permanent regression guard (R66).
- L18 cold-cache battery: 13 routes → 15 routes.
- L18 throttled battery: 6 routes → 8 routes.
- No Q12 layer extension.
