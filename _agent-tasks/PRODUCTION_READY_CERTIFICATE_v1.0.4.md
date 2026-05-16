# PRODUCTION READY CERTIFICATE — ABS Server v1.0.4

**Date issued:** 2026-05-16
**Tag:** `v1.0.4` → commit `f433dcb` on `main`
**Footer:** 🟢 GREEN — ALL workflows + docs site green
**Caveats:** none (Sprint 2N.2 v1.0.3 yellow-docs gap closed by 2N.3)

## Why v1.0.4 supersedes v1.0.3

v1.0.3 was 🟢 green for image-ship + CI test/build/security workflows
but 🟡 yellow on the docs site auto-deploy (docs run 25968243819 failed
with `duplicated version and alias`). v1.0.4 ships the single-fix
docs alias split — `MIKE_VERSION` derived from git ref instead of the
hard-coded `latest` default — and was the first tag whose docs
workflow returned success.

Image content is unchanged from v1.0.3 (no source / test diff). Backend
+ landing were rebuilt and re-tagged `:1.0.4` + `:latest` by the same
`publish-images` job that shipped v1.0.3.

## CI status (v1.0.4 push, sha `f433dcb`)

| Workflow | Run | Conclusion |
|----------|------|------------|
| Release | 25968714837 | ✅ success |
| SBOM Generation | 25968714849 | ✅ success |
| docs | 25968714499 | ✅ success — first green after 5 sequential fails |
| CodeQL Advanced | 25968714494 | ✅ success |
| CI Postgres (RLS) | 25968714492 | ✅ success |

5/5 GREEN.

## Live surfaces

- `https://docs.automatiabcn.com/v1.0.4/` — 200 OK
- `https://docs.automatiabcn.com/` (alias `latest`) — 200 OK
- `ghcr.io/automatiabcn/abs-backend:1.0.4` — 401 anonymous (auth gate
  expected); `docker pull` with login OK
- `ghcr.io/automatiabcn/abs-landing:1.0.4` — same

## Pytest

Inherited from Sprint 2N.2 — `2171 passed, 24 skipped, 3 deselected`.
No source / test diff in 2N.3.

## Customer upgrade

See `_agent-tasks/SMEBES_UPGRADE_v1_0_4.md` for the founder
one-paste command (incl. rollback to v1.0.3 if needed).

## Footer

- 🟢 GREEN end-to-end: image-ship, CI test/build/security, docs site.
- Pilot Batch 2 GO/NO-GO: **GO** on every gate.
- No outstanding hot-patch chain.
