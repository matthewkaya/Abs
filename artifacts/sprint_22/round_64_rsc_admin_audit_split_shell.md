# Round 64 — Sprint 22 RSC Phase B leg 1: `/admin/audit` split-shell

**Layer:** Sprint 22 RSC migration (Q12 S8 brief HIGH #3)
**Status:** ✅ ship — split-shell live, 6/6 Playwright PASS across chromium + firefox + webkit
**Time:** 2026-05-04

## Goal

Per the R59 audit decision: `/admin/audit` is a poor candidate for full RSC because the page is interactive (filter inputs + chain-verify state + 30s react-query refetch). The right pattern is **split-shell**: a server component does the initial fetch, then mounts a client island that owns interactivity.

## What changed

| File | Kind | Note |
|------|------|------|
| `core/landing/app/admin/audit/page.tsx` | rewrite | server component; awaits `cookies()`, fetches `/v1/admin/audit/recent?limit=200` server-side with the caller's `abs_session` forwarded, falls back to MOCK_AUDIT on any failure, renders `<AuditClient initialEntries={...}>` |
| `core/landing/app/admin/audit/AuditClient.tsx` | new | the previous whole-page client component verbatim, minus the MOCK fallback (now lives server-side); `useQuery` seeds from `initialData: initialEntries` so first paint already has rows |
| `core/landing/app/admin/audit/types.ts` | new | shared `AuditEntry` interface + MOCK_AUDIT fixture so server and client agree on shape |
| `core/landing/__tests__/playwright/q12-r64-rsc-audit-split-shell.spec.ts` | new | 2 scenarios × 3 browsers = **6/6 PASS** in 11.9 s |

## Smoke evidence

```
$ curl -sk -L -b /tmp/q12_cookie.txt http://localhost:3457/admin/audit \
       -o /tmp/audit_page.html -w "code=%{http_code}\n"
code=200

$ curl -sk -b /tmp/q12_cookie.txt http://localhost:8000/v1/admin/audit/recent?limit=200
{"source":"all","count":0,"entries":[]}    status=200

$ for i in 1 2 3; do curl -sk -L -b /tmp/q12_cookie.txt \
    http://localhost:3457/admin/audit -o /dev/null \
    -w "warm_${i} ttfb=%{time_starttransfer}s total=%{time_total}s size=%{size_download}\n" \
    -m 30; done
warm_1 ttfb=0.056715s total=0.059237s size=80180
warm_2 ttfb=0.043617s total=0.045680s size=80181
warm_3 ttfb=0.043065s total=0.045684s size=80181
```

The HTML carries `data-page="admin-audit"` and renders `<h1>Denetim</h1>` server-side. With `entries: []` from the local backend, the server-rendered DOM also includes `Filtreyle eşleşen olay yok` (the empty-state text) because React Query's `initialData` is consumed during SSR. With entries the `<ul>` of `<li data-test="audit-row">` would be rendered before any client refetch fires — the spec asserts whichever branch the local fixture picks.

## Cross-browser parity

```
[chromium-desktop] page renders heading + filter inputs            ✓ 2.7s
[chromium-desktop] server initial fetch payload is in HTML         ✓ 2.7s
[firefox-desktop]  page renders heading + filter inputs            ✓ 4.0s
[firefox-desktop]  server initial fetch payload is in HTML         ✓ 3.8s
[webkit-desktop]   page renders heading + filter inputs            ✓ 4.0s
[webkit-desktop]   server initial fetch payload is in HTML         ✓ 3.5s
6 passed (11.9s)
```

## What R64 does NOT do

- Lighthouse before/after measurement is R66, not R64. The +400 ms
  slow-3G LCP target is on R66's plate.
- `/admin/users` migration is R65 — same shape, different state shape
  (mutation + invite/revoke).

## Image rebuild gate

Backend untouched — no rebuild. Frontend dev (3457) reload picked up the new server component automatically; warm hits are <60 ms TTFB.

## Layer state delta

- Sprint 22 RSC Phase B leg 1: ✅ shipped.
- Q11-L11 cross-browser webkit: +1 spec (R64 split-shell) on top of R63's 4-spec set.
- No Q12 layer extension (Sprint 22 work).

## Diff summary

```
A  core/landing/app/admin/audit/AuditClient.tsx                       (~250 lines, hot path of original page.tsx)
A  core/landing/app/admin/audit/types.ts                              (~55 lines, shared shape)
M  core/landing/app/admin/audit/page.tsx                              (rewrite, ~50 lines, server component)
A  core/landing/__tests__/playwright/q12-r64-rsc-audit-split-shell.spec.ts  (~100 lines, 2 scenarios × 3 browsers = 6/6 PASS)
A  artifacts/sprint_22/round_64_rsc_admin_audit_split_shell.md
M  artifacts/sprint_q12/master_audit_summary.md
```
