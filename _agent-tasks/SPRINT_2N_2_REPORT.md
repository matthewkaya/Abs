# SPRINT 2N.2 — Hot-patch closeout

**Date:** 2026-05-16
**Branch merged:** `feat/sprint-2n-2-hot-patch` → `main` (commit `900e65c`)
**Tag:** `v1.0.3` (annotated `a444d61` → commit `900e65c`)
**Predecessor:** Sprint 2N.1 (tag `v1.0.2` shipped GitHub Release entry
only — no GHCR images, no docs deploy)
**Successor:** Sprint 2N.3 single-fix docs patch (already cut on
`feat/sprint-2n-3-hot-patch`, awaits founder push)

## Outcome

| Gap (from v1.0.2 audit) | Sprint 2N.2 fix | CI status post-v1.0.3 |
|-------------------------|------------------|------------------------|
| Backend image push: `manifest_pubkey.pem` missing | 2N.2-A — Dockerfile path → `app/update/manifest_pubkey.pem` | Release backend GREEN |
| Landing image push: `permission_denied` on `enzoemir1` | 2N.2-B — namespace `enzoemir1` → `automatiabcn` (workflow + customer compose + scripts + tests) | Release landing GREEN |
| docs `duplicated version and alias` | 2N.2-C — `mike delete` koşulsuz | **NOT CLOSED** — alias-only delete leaves version; deploy still collides |
| CI Postgres (RLS) 5 test fail | 2N.2-D — two-role split + NullPool + LOGIN/grant restore | CI Postgres GREEN (7/7) |

**Real GA criterion:** customer image ships under a workflow-pushable
namespace. v1.0.3 is the first tag for which `docker manifest inspect
ghcr.io/automatiabcn/abs-{backend,landing}:1.0.3` returns 200.
Pre-v1.0.3 the manifest did not exist.

## GHCR evidence

```
ghcr.io/automatiabcn/abs-backend:1.0.3
  amd64 sha256:459bb68e9ad8b68e93d127cc75f49bb0b9c0124c6175ce1d7590dc1149f6db83
ghcr.io/automatiabcn/abs-landing:1.0.3
  amd64 sha256:8c51aca0d591cf6fe47011ce412d4cf1e9325aa3cfcf72fbe8b3e3ba6f2436e2
```

Both also published as `:latest` (same digest). OCI multi-platform index
+ cosign keyless attestation present.

## CI matrix (v1.0.3 push)

| Workflow | Run id | Conclusion | Notes |
|----------|--------|------------|-------|
| Release | 25968244147 | success | 4/4 jobs incl. cosign keyless |
| SBOM Generation | 25968244153 | success | CycloneDX attached as release asset |
| CI Postgres (RLS) | 25968243828 | success | FAZ D verify — 7/7 GREEN |
| CodeQL Advanced | 25968243837 | success | no new findings |
| docs | 25968243819 | **failure** | `mike deploy` duplicated version+alias |

## docs FAIL — sharp disclosure

- Trigger: `event=push branch=main` (NOT v1.0.3 tag — docs.yml only
  subscribes to `push:branches:[main]` + `release:published`, not tag
  push, so v1.0.3 didn't produce a separate docs run).
- 2N.2-C left the workflow input default `version: latest` and the
  deploy step used `MIKE_VERSION: ${{ inputs.version || 'latest' }}`,
  yielding the literal pair `mike deploy --update-aliases latest latest`.
  `mike delete latest` removes only the alias, leaving the *version*
  named `latest`, so the next deploy re-collides.
- Confirmed by the run's "Deploy with mike (versioned, idempotent)"
  log line `MIKE_VERSION: latest` and the `error: duplicated version
  and alias` exit code 1.
- Resolution lives on `feat/sprint-2n-3-hot-patch` (commit `3e41dc1`,
  unpushed at the time of this report): new "Resolve mike version
  label" step derives `MIKE_VERSION` from `github.ref_name`
  (`v1.0.x` for tag/release, `main` for branch push). Alias `latest`
  stays as the only alias label; pre-delete keeps stderr visible.

## Local pytest

`2171 passed, 24 skipped, 3 deselected, 58 warnings` (SQLite baseline
preserved through 2N.2-D's CI-only role split).

## What landed where

- 4 fix commits on `feat/sprint-2n-2-hot-patch`, plus the merge commit
  on `main`. After the founder filter-branch rewrite (trailer scrub on
  2026-05-16), the merge commit hash is `900e65c`; the per-fix commits
  retain the same patch content with new hashes.
- Customer compose now reads `ABS_GHCR_NAMESPACE` (default
  `automatiabcn`). Existing `enzoemir1` pins keep working via
  `ABS_GHCR_NAMESPACE=enzoemir1` in `.env`.
- `core/backend/Dockerfile`, `infra/docker-compose.customer.yml`,
  `docker-compose.yml`, `scripts/release.sh`,
  `scripts/customer_onboard.sh`, and one IP-hardening test were
  updated. `core/backend/alembic/env.py` stays as 2N.1 left it.

## Sprint 2N.3 plan (next chain link)

Single-fix patch.

1. `fix(2n.3-a): derive mike version from git ref`
   (already on `feat/sprint-2n-3-hot-patch`, commit `3e41dc1`).
2. Re-cycle: founder merges `feat/sprint-2n-3-hot-patch` → main,
   `git filter-branch` to scrub any AI-tool trailers, force-push main,
   tag `v1.0.4`, push tag.
3. Wait for docs workflow GREEN; verify
   `https://docs.automatiabcn.com/v1.0.3/` (or `/v1.0.4/`) renders.
4. Close this report's docs row in CHANGELOG v1.0.4 entry.

## Customer / smebes upgrade

```
# Founder one-paste on smebes server
cd /opt/abs   # or whatever the install path is
sed -i 's/^ABS_VERSION=.*/ABS_VERSION=1.0.3/' .env
grep -q '^ABS_GHCR_NAMESPACE=' .env || echo 'ABS_GHCR_NAMESPACE=automatiabcn' >> .env
docker compose -f infra/docker-compose.customer.yml pull
docker compose -f infra/docker-compose.customer.yml up -d
curl -sf https://${ABS_PUBLIC_HOSTNAME}/healthz && echo "healthz OK"
curl -sf https://${ABS_PUBLIC_HOSTNAME}/readyz  && echo "readyz OK"
```

Pilot Batch 2 metadata bump: v1.0.2 → v1.0.3; contract delivery line
unchanged.
