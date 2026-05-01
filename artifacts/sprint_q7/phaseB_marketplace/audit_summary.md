# Q7 Phase B — Plugin Marketplace Hardening — Audit Summary

**Date:** 2026-04-30
**Sprint / Phase:** Q7 / Phase B
**Owner:** marketplace track
**Status:** SHIPPED

---

## 1. Scope & Pre-approved Decisions

| Decision | Value |
|----------|-------|
| Stub plugin image | `busybox:1.36` + `healthcheck.sh` (real images Q8) |
| Cosign verification | dev skip-mode default (`ABS_COSIGN_SKIP=true`); graceful fallback when binary missing |
| Sandbox SDK | `docker` Python SDK — soft import; install flow degrades to `installed_no_sandbox` when missing |

## 2. Files Created / Modified

| Action | Path | Notes |
|--------|------|-------|
| NEW | `core/backend/app/marketplace/cosign_verify.py` | `verify_signature(image, expected_signature, public_key_path)` + skip-mode |
| EXTEND | `core/backend/app/marketplace/sandbox.py` | Appended `PluginSandbox` class (launch/stop/status); existing G1-hardened exports untouched |
| MODIFY | `core/backend/app/api/marketplace.py` | install: cosign gate + sandbox launch + record enrichment; new `DELETE /uninstall/{plugin_id}`; `/installed` enriched with `live_status`; tenant-claim isolation |
| MODIFY | `core/backend/app/config.py` | `cosign_skip: bool = True`, `cosign_public_key_path: str` (after T-018 anchor) |
| NEW | `core/backend/tests/test_marketplace_hardening.py` | 7 edge cases + 1 live-docker smoke (skipped unless `ABS_DOCKER_LIVE=1`) |
| NEW | `infra/plugins/busybox-stub/Dockerfile` | non-root, healthcheck, sleep loop |
| NEW | `infra/plugins/busybox-stub/healthcheck.sh` | always-healthy stub |
| NEW | `artifacts/sprint_q7/phaseB_marketplace/repro.sh` | live-server PASS/FAIL harness |
| NEW | `artifacts/sprint_q7/phaseB_marketplace/audit_summary.md` | this doc |

Total: **9 deliverables** (3 new code, 3 modified code, 3 infra/artifacts).

## 3. Test Coverage (`test_marketplace_hardening.py`)

| # | Test | Asserts |
|---|------|---------|
| 1 | `test_install_with_cosign_skip` | 201 + `sandbox_status` ∈ {`installed_no_sandbox`, `running`} |
| 2 | `test_install_invalid_signature_rejected` | 403 `signature_invalid` (verify_signature monkeypatched to False) |
| 3 | `test_idempotent_install` | 1st 201; 2nd 200 `already_installed` |
| 4 | `test_uninstall_removes_record` | 200 `uninstalled`; subsequent `/installed` empty |
| 5 | `test_uninstall_not_found` | 404 `not_installed` |
| 6 | `test_cross_tenant_isolation` | dependency_overrides → admin tenant=A; query tenant=B → 403; tenant=A → 200 |
| 7 | `test_install_5_plugins_then_list` | All catalog ids round-trip via `/installed` |
| L | `test_live_docker_launch_smoke` | Gated on `ABS_DOCKER_LIVE=1`; real launcher round-trip |

7 unit + 1 live-skip = **8 tests** in this file.

## 4. Behaviour Notes

- **Cosign skip-mode** (`settings.cosign_skip=True`): signature verification short-circuits to `True`. Production deployments must set `ABS_COSIGN_SKIP=false` and provide `ABS_COSIGN_PUBLIC_KEY_PATH`.
- **Docker SDK absent**: `PluginSandbox.__init__` raises `RuntimeError`. Both install + uninstall + list endpoints catch and degrade gracefully (logged warning, persistence still succeeds).
- **Tenant isolation** uses an opt-in claim (`admin["tenant"]`). When the admin token carries no tenant claim the guard is a no-op so existing single-tenant dev/test flows keep working. Real multi-tenant claim mint lands later in the OAuth track.
- **Idempotent install**: catalog lookup + cosign gate run *before* the duplicate-check, so an invalid signature on a re-install attempt is still rejected.
- **`/installed` enrichment**: each row gains a `live_status` key when the docker SDK is available; otherwise the unmodified persisted record is returned.

## 5. Edge Cases Covered

| Case | Mechanism |
|------|-----------|
| Cosign skip-mode (dev) | autouse fixture sets `cosign_skip=True` |
| Cosign hard-fail | monkeypatch on module-level `verify_signature` |
| Replay install | bucket scan returns `already_installed` |
| Stale install record | uninstall path handles + best-effort sandbox stop |
| Missing record | 404 `not_installed` |
| Cross-tenant query | `_enforce_tenant_match` 403 + dependency_overrides test |
| Catalog round-trip | 5/5 ids returned post-install |
| Docker daemon missing | install/uninstall/list all degrade gracefully |

## 6. Repro

```bash
bash artifacts/sprint_q7/phaseB_marketplace/repro.sh
```

Requires backend running at `http://localhost:8000`. Asserts:
- 5 plugin installs (201)
- listed count == 5
- idempotent install (200, `already_installed`)
- DELETE /uninstall (200)
- DELETE /uninstall again (404)

## 7. Constraints Honoured

- No `pip install` performed; `docker` Python SDK is *not* added to `pyproject.toml`. Install path remains green via graceful fallback when the SDK is absent (note: requirements.txt does not yet include `docker`; recommended to add in Q8 once the launcher is wired into the live deploy).
- No docker daemon commands executed during this phase.
- Phase A files untouched: `app/integrations/neo4j_client.py`, `app/api/graph.py`, `app/main.py`, `infra/docker-compose.dev.yml`.
- Phase C files untouched: `core/landing/**`.
- Existing `PLUGIN_CATALOG` (5 entries) and `core/backend/app/marketplace/sandbox.py` exports preserved.

## 8. Exit Gate

| Gate | Status |
|------|--------|
| 7 hardening tests written | DONE |
| Cosign skip-mode + hard-fail covered | DONE |
| Idempotent install + uninstall + 404 | DONE |
| Cross-tenant 403 guard | DONE |
| Docker SDK degradation | DONE |
| Stub image + healthcheck shipped | DONE |
| Repro script + audit doc | DONE |
| `pyproject.toml` left untouched | DONE |

PASS — Phase B closed. Q8 follow-ups: (a) add `docker>=7` to `pyproject.toml`, (b) wire `PluginSandbox` into live deploy + reconcile loop, (c) replace stub busybox image with publisher-signed `ghcr.io/automatiabcn/abs-plugin-*` images and flip `ABS_COSIGN_SKIP=false` in prod.
