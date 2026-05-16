# Sprint 2N.3 — LIGHT closeout (docs alias split, v1.0.4 GA)

**Date:** 2026-05-16
**Tag:** `v1.0.4` (annotated → commit `f433dcb` on `main`)
**Predecessor:** Sprint 2N.2 / v1.0.3 (closeout `73a9a62`; docs gap was the only RC blocker)
**Successor:** none scheduled; image-ship + docs-site both GREEN

## Scope (single fix)

| FAZ | Change | Outcome |
|-----|--------|---------|
| A | `docs.yml` — new "Resolve mike version label" step derives `MIKE_VERSION` from `github.ref_name` (tag → `v1.0.x`, branch push → `main`, dispatch → input). Deploy uses that version with `--update-aliases latest` so version and alias never collide. Pre-delete keeps stderr visible. | docs workflow GREEN for the first time in 5 attempts |

Commit: `3e41dc1 fix(docs): derive mike version from git ref (close v1.0.3 duplicated alias)`
Merge commit: `f433dcb`

## Founder push procedure used

```
git checkout main
git merge feat/sprint-2n-3-hot-patch --no-ff -m "merge: Sprint 2N.3 docs hot-patch ..."
# Pre-push trailer/brand grep — returned EMPTY, scrub step skipped
git diff HEAD~1..HEAD | grep -iE "${BANNED_PATTERN}"
git tag -a v1.0.4 -m "ABS v1.0.4 — Sprint 2N.3 docs mike alias split (closes 2N.2 docs gap)"
git push origin main v1.0.4
```

The 2N.1+2N.2 `filter-branch` recipe was unnecessary here — the
pre-merge grep gate confirmed zero tool-attribution leaks in either
the single fix commit or the merge commit message.

## CI status (v1.0.4 push, sha `f433dcb`)

| Workflow | Run | Conclusion |
|----------|------|------------|
| Release | 25968714837 | success |
| SBOM Generation | 25968714849 | success |
| docs | 25968714499 | success (FIRST GREEN after 5 sequential failures) |
| CodeQL Advanced | 25968714494 | success |
| CI Postgres (RLS) | 25968714492 | success |

5/5 GREEN.

## Live surfaces

- `https://docs.automatiabcn.com/v1.0.4/` — 200 OK
- `https://docs.automatiabcn.com/` (alias `latest`) — 200 OK
- `ghcr.io/automatiabcn/abs-backend:1.0.4` — 401 on anonymous (auth gate
  normal), `docker pull` with login OK
- `ghcr.io/automatiabcn/abs-landing:1.0.4` — same

## Pytest

Inherited from Sprint 2N.2 — 2171 passed, 24 skipped, 3 deselected.
No source / test changes in 2N.3, so no re-run needed.

## What's NOT in this closeout

- Heavy cert refresh — `PRODUCTION_READY_CERTIFICATE_v1.0.4.md` only
  flips the v1.0.3 "yellow docs" caveat to green; no other gates moved.
- Memory milestone is a 1-paragraph snapshot, not a full session-resume.

## Next

- Smebes upgrade pkg: see `_agent-tasks/SMEBES_UPGRADE_v1_0_4.md`
  (founder one-paste, rollback included).
- Pilot Batch 2: image-ship + docs-site both GREEN → full GO.
