# PRODUCTION READY CERTIFICATE — ABS Server v1.0.3

**Date issued:** 2026-05-16
**Tag:** `v1.0.3` (annotated `a444d61` → commit `900e65c` on `main`)
**Footer:** 🟢 GREEN — image-ship verified
**Caveat:** 🟡 docs site auto-deploy gap open (Sprint 2N.3 in flight)

## Why v1.0.3 supersedes v1.0.0 / v1.0.1 / v1.0.2

| Tag | Tag commit on remote | Customer image shipped? |
|-----|-----------------------|--------------------------|
| v1.0.0 | yes | yes (`ghcr.io/enzoemir1/abs-*:1.0.0`, founder-published manually) |
| v1.0.1 | yes | yes (`enzoemir1` namespace) |
| v1.0.2 | yes | **no** — release.yml's new push step failed (`manifest_pubkey.pem` not found + cross-namespace `permission_denied`) |
| **v1.0.3** | yes | **yes** — `ghcr.io/automatiabcn/abs-{backend,landing}:1.0.3` 200 OK |

v1.0.0 and v1.0.1 stay valid for any pilot still pinned to the
`enzoemir1` namespace; v1.0.3 is the first tag where the publishing
workflow self-serves (no founder PAT push), unlocking smebes upgrade
and Pilot Batch 2 without manual intervention.

## CI status (post-tag push)

| Workflow | Run | Conclusion |
|----------|------|------------|
| Release | 25968244147 | ✅ success (publish-images backend + landing + cosign keyless) |
| SBOM Generation | 25968244153 | ✅ success (CycloneDX attached as release asset) |
| CI Postgres (RLS) | 25968243828 | ✅ success — 7/7 GREEN (FAZ D verify) |
| CodeQL Advanced | 25968243837 | ✅ success |
| docs | 25968243819 | ❌ failure — `duplicated version and alias`; Sprint 2N.3 patch on `feat/sprint-2n-3-hot-patch` (`3e41dc1`) |

## GHCR evidence

```
ghcr.io/automatiabcn/abs-backend:1.0.3
  amd64 sha256:459bb68e9ad8b68e93d127cc75f49bb0b9c0124c6175ce1d7590dc1149f6db83
ghcr.io/automatiabcn/abs-landing:1.0.3
  amd64 sha256:8c51aca0d591cf6fe47011ce412d4cf1e9325aa3cfcf72fbe8b3e3ba6f2436e2
```

Both `:1.0.3` and `:latest` resolve to the same digest. OCI multi-platform
index + cosign keyless attestation.

## Pytest

- 2171 passed, 24 skipped, 3 deselected (full SQLite suite)
- CI Postgres (RLS) 7/7 GREEN, module order independent

## What 2N.2 fixed (vs v1.0.2)

| # | Fix | Outcome |
|---|-----|---------|
| 2N.2-A | Dockerfile pubkey path → `app/update/manifest_pubkey.pem` | backend image now builds in CI checkout |
| 2N.2-B | GHCR namespace `enzoemir1` → `automatiabcn` | workflow GITHUB_TOKEN can push; landing 200 OK |
| 2N.2-C | docs mike pre-delete koşulsuz (partial) | alias removed but version still collides — 2N.3 closes |
| 2N.2-D | RLS test fixture two-role split + NullPool | CI Postgres 5 fail → 7/7 GREEN |

## Outstanding (does NOT block image-ship GA)

- **docs.automatiabcn.com** v1.0.3 sayfası deploy edilmedi (mike
  duplicate). GitHub Release notes + `docs/CHANGELOG.md` v1.0.3
  entry kanonik.
- Sprint 2N.3 closes this — single fix, single commit
  (`feat/sprint-2n-3-hot-patch:3e41dc1`), no source-of-truth content
  changes.

## Customer / smebes upgrade (founder one-paste)

```
cd /opt/abs   # actual install path
sed -i 's/^ABS_VERSION=.*/ABS_VERSION=1.0.3/' .env
grep -q '^ABS_GHCR_NAMESPACE=' .env || echo 'ABS_GHCR_NAMESPACE=automatiabcn' >> .env
docker compose -f infra/docker-compose.customer.yml pull
docker compose -f infra/docker-compose.customer.yml up -d
curl -sf https://${ABS_PUBLIC_HOSTNAME}/healthz && echo "healthz OK"
curl -sf https://${ABS_PUBLIC_HOSTNAME}/readyz  && echo "readyz OK"
```

Pre-2N.2 pinned customers: keep `ABS_GHCR_NAMESPACE=enzoemir1`; founder
dual-publishes with `GHCR_USER=enzoemir1 ./scripts/release.sh 1.0.3` if
needed.

## Footer

- 🟢 GREEN for image-ship and CI test/build/security workflows
- 🟡 docs site auto-deploy open (Sprint 2N.3, single commit ready)
- Pilot Batch 2 GO/NO-GO: **GO** for image-ship; **NO-GO** until docs
  site reflects v1.0.3 changelog publicly (~1 day, gated on Sprint
  2N.3 push)
