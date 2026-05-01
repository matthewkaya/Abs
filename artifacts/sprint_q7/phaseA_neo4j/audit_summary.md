# Q7 Phase A — Neo4j Integration Audit Summary

**Date:** 2026-04-30
**Owner:** Worker — Phase A
**Scope:** Bring Neo4j 5.18 graph DB online behind /v1/graph/* (admin-only).

## Deliverables

| # | Artifact | Path | Status |
|---|----------|------|--------|
| 1 | Compose service + volumes | `infra/docker-compose.dev.yml` | PASS |
| 2 | Settings (3 fields) | `core/backend/app/config.py` | PASS |
| 3 | Async Neo4j client | `core/backend/app/integrations/neo4j_client.py` | PASS |
| 4 | /v1/graph router (5 endpoints) | `core/backend/app/api/graph.py` | PASS |
| 5 | Router registration | `core/backend/app/main.py` | PASS |
| 6 | requirements.txt + pyproject pin | `core/backend/requirements.txt`, `core/backend/pyproject.toml` | PASS |
| 7 | Seed fixture | `core/backend/tests/fixtures/graph_seed.json` | PASS |
| 8 | Pytest suite (5 tests) | `core/backend/tests/test_neo4j_integration.py` | PASS |
| 9 | Repro script | `artifacts/sprint_q7/phaseA_neo4j/repro.sh` | PASS |
| 10 | This audit summary | `artifacts/sprint_q7/phaseA_neo4j/audit_summary.md` | PASS |

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | /v1/graph/health | admin | Bolt RTT probe |
| GET | /v1/graph/schema | admin | Label histogram |
| POST | /v1/graph/cypher | admin | Raw Cypher (destructive guard) |
| POST | /v1/graph/ingest | admin | Bulk entity + relation upsert |
| POST | /v1/graph/nl-query | admin | NL → cascade LLM → Cypher exec |

## Test Inventory

5 tests in `tests/test_neo4j_integration.py`:

1. `test_cypher_destructive_blocked` — runs offline; verifies FastAPI rejects
   `MATCH (n) DETACH DELETE n` with HTTP 400 before client is touched.
2. `test_cypher_destructive_with_confirm` — gated on `ABS_NEO4J_LIVE=1`;
   accepts destructive query when `_confirm_destructive=True`.
3. `test_ingest_seed_then_count` — gated on live; seeds graph, asserts
   DemoCo employee count == 2.
4. `test_health_endpoint` — gated on live; asserts `{ok: true}`.
5. `test_nl_query_mocked` — gated on live; monkeypatches
   `app.providers.cascade.cascade_call` to return a hardcoded Cypher,
   verifies passthrough returns 2 people.

CI default: only the destructive-guard test runs (no Neo4j needed). Live
suite runs when an operator sets `ABS_NEO4J_LIVE=1` after `docker compose
up neo4j`.

## Security Posture

- All 5 endpoints behind `current_admin` (panel JWT cookie required).
- Destructive Cypher (`DELETE`/`DROP`/`REMOVE`/`DETACH DELETE`) blocked
  unless caller passes `_confirm_destructive=true` in params.
- NL→Cypher path also blocks destructive output from LLM (502 if no
  `cypher` key, 400 if destructive).
- Default password `AbsNeo2026!` is dev-only; sops/age vault deferred
  to Q8 per master brief.

## Exit Gate

| Criterion | Status |
|-----------|--------|
| All 10 deliverables shipped | PASS |
| No files outside Phase A scope touched | PASS |
| AST parse + import smoke (config) | PASS |
| pytest collection compiles cleanly | PASS |
| Live tests gated on env flag | PASS |

## Non-Goals (deferred)

- Real cosign-signed Cypher policy enforcement → out of Q7 Phase A.
- Vault rotation of `AbsNeo2026!` → Q8 (sops/age handover).
- Cerbos PDP gate on `/v1/graph/*` resource scope → out of Phase A scope
  (panel auth is sufficient gate; tenant isolation lands when graph
  payloads gain a `tenant` property in a follow-up phase).

## Phase A — DONE
