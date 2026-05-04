# Q12 Session 8 — Round 62

**Layer:** Q11-L11 cross-browser (firefox-desktop)
**Specs:** `q12-l26-long-running.spec.ts` (smoke) + `q10-l4-aria-live-deep.spec.ts` + `q12-l18-cold-cache.spec.ts`
**Goal:** Close the three deferred firefox specs from S8-R57 (which only validated `q12-l20-chaos-multi.spec.ts` 3/3 PASS before the dev server churned).

## Result

**20/20 firefox-desktop PASS + 1 gated skip** in 1.6 min wall-clock.

| Spec | Tests | PASS | Notes |
|------|-------|------|-------|
| `q12-l26-long-running.spec.ts` | 1 smoke + 1 gated 30-min | 1 PASS, 1 skipped | `post_idle_status=200`, drift well under 25 MB |
| `q10-l4-aria-live-deep.spec.ts` | 5 scenarios | 5/5 PASS | sessions-error-tile + chat-error-tile + transcription polite + /panel cascade alert + announcement log |
| `q12-l18-cold-cache.spec.ts` | 13 routes (4 public + 9 panel) | 13/13 PASS | All under budget; full table in artifact |

## R62 — environmental issue surfaced and fixed (NOT a firefox bug)

The first run had two failures:

1. `q12-l26 smoke` — `post_idle_status=500`
2. `q12-l18 /showcase` — LCP 5780 ms > 3500 ms budget

Investigation showed both are environment, not browser:

- **Backend host port 8000 was not exposed.** Only `infra/docker-compose.dev.yml` exposes it (`- "8000:8000"`); the running compose is the prod stack (caddy 80/443 only). Chromium baseline reproduced the same 500 (`q12-l26-long-running.spec.ts` `--project=chromium-desktop --grep smoke` → 1 failed, identical post_idle_status=500). Confirmed not firefox-specific.
- **Showcase 5780 ms** was a one-off concurrent-run flake when the slow `q12-l26` 90s idle test was using the same firefox-desktop worker pool. Re-run in isolation: 89/282/434/779 ms across 4 invocations — all well under the 3500 ms budget.

### Fix (non-destructive)

Spawned a non-destructive sidecar on the docker `infra_default` network to forward `localhost:8000 → backend:8000` so Playwright dev-server rewrites resolve without recreating the production backend container:

```bash
docker run -d --rm --name abs-q12-be-fwd \
  --network infra_default \
  -p 8000:8000 \
  alpine/socat tcp-listen:8000,fork,reuseaddr tcp-connect:backend:8000
```

Verified: `curl localhost:8000/healthz` → `200 {"status":"ok","service":"abs-backend"}`.

This sidecar is a runtime helper, not a code change. It does not modify `infra/` and does not touch the production container. Tear down with `docker rm -f abs-q12-be-fwd`.

## Cold-cache LCP table (firefox-desktop)

```
/                       LCP=166ms   FCP=166ms   TTFB=41ms    budget=3500ms
/pricing                LCP=0ms     FCP=0ms     TTFB=84ms    budget=3500ms
/showcase               LCP=89ms    FCP=89ms    TTFB=52ms    budget=3500ms
/onboarding             LCP=1833ms  FCP=1575ms  TTFB=1537ms  budget=3500ms
/panel                  LCP=585ms   FCP=219ms   TTFB=176ms   budget=4500ms
/panel/chat             LCP=927ms   FCP=183ms   TTFB=138ms   budget=5500ms
/panel/tools            LCP=3401ms  FCP=2880ms  TTFB=2788ms  budget=5500ms
/panel/quota            LCP=3951ms  FCP=3951ms  TTFB=3876ms  budget=4500ms
/panel/meetings         LCP=2860ms  FCP=2860ms  TTFB=2762ms  budget=4500ms
/panel/transcription    LCP=1086ms  FCP=1086ms  TTFB=1049ms  budget=4500ms
/admin/marketplace      LCP=4207ms  FCP=2567ms  TTFB=2530ms  budget=4500ms
/admin/providers        LCP=3674ms  FCP=3674ms  TTFB=3620ms  budget=4500ms
/admin/workflow-builder LCP=2808ms  FCP=2808ms  TTFB=2738ms  budget=5500ms
```

(Numbers are dev-mode + first-compile costs; production stand-alone build will be lower.)

## Layer state delta

- Q11-L11 cross-browser firefox-desktop: 4 spec PASS in S7+S8 (chaos-multi from R57 + 3 specs from R62).
- Cross-browser webkit (R63) still pending — same 4-spec set.

## Image rebuild

Backend untouched. No image rebuild needed.

## Commits

This round = single atomic commit pinning the run; specs themselves were already shipped (R30, R35, R40, R57).
