# SPRINT_2K_PREFLIGHT — Postgres RLS Migration (Defence-in-Depth)

**Date:** 2026-05-14
**Branch:** `feat/sprint-2k-postgres-rls-migration` (from Sprint 2J HEAD `705f977`)
**Brief:** `_agent-tasks/WORKER_SPRINT_2K_POSTGRES_RLS_MIGRATION_BRIEF.md`
**Source plan:** `_research/postgres_rls_plan.md` (Sprint 2I FAZ C2 scaffold, 97 lines)
**Motivation:** `_agent-tasks/AUDIT_3RD_EYE_2026_05_14.md` finding #16 — Postgres-level RLS missing; app-filter + Cerbos PDP are layers 1-2, RLS is the third.

---

## 1. Baseline Confirmation

| Item | Expected | Observed |
|------|----------|----------|
| Branch source | `feat/sprint-2j-customer-onboarding-e2e` @ `705f977` | ✓ checked out, new branch cut |
| Backend pytest | 2126 / 0 / 21 skip (Sprint 2J final) | Running (background, see SPRINT_2K_BASELINE_PYTEST.txt) |
| Frontend vitest | 172 / 172 (Sprint 2J final) | Deferred to post-merge gate |
| Alembic head | `0013_failed_login_attempts` | ✓ confirmed (`core/backend/alembic/versions/` listing) |
| Audit tables in scope | `customer_audit_entries`, `webhook_events`, `vault_audit_entries` | ✓ confirmed in `core/backend/app/db/models.py` |

## 2. Decision-Point Defaults (founder-overridable post-merge)

The scaffold plan (`postgres_rls_plan.md` §"Decision points") lists three open
items. Sprint 2K ships with the **safer / more auditable** default for each and
documents the alternative so Sprint 2L can revisit once production telemetry
arrives.

### 2.1 Admin bypass strategy → `abs_admin` role with `BYPASSRLS`
- **Chosen:** Dedicated Postgres role (`abs_admin`) that owns `BYPASSRLS`.
  Production DSN for the admin-console pool uses this role; the application
  pool uses a non-bypass role (`abs_app`).
- **Rejected (Sprint 2L candidate):** Policy clause `USING (true OR tenant_id
  = current_setting(...))` gated on a session GUC like `abs.admin = 'true'`.
  Simpler ops but harder to audit (a forgotten GUC reset becomes a silent
  cross-tenant read).
- **Rationale:** A role boundary is observable in `pg_stat_activity`; a GUC
  boundary is not. With Sprint 2 still pre-pilot we choose the boundary
  auditors will recognise.

### 2.2 Customer self-host posture → Multi-tenant deployments only
- **Chosen:** RLS migration applies unconditionally on Postgres. Single-tenant
  self-host installs (`ABS_DEPLOY_MODE=single-tenant`) are unaffected at the
  policy layer — there is only one tenant so the GUC always matches.
- **Rejected:** Conditional migration gated on `ABS_DEPLOY_MODE`. Adds a
  branch in the schema lifecycle and produces two prod topologies to support.
- **Rationale:** A no-op-for-single-tenant policy costs zero and keeps the
  schema invariant identical everywhere.

### 2.3 SQLite test gap → Accept
- **Chosen:** RLS is Postgres-only. SQLite test suite keeps the
  application-level tenant filter as its single guard; the new CI matrix
  postgres lane (FAZ F) runs the RLS integration suite against Postgres 15.
- **Rejected:** A SQLite shim that fakes RLS via triggers. Significant
  engineering, low ROI, never the same semantics.
- **Rationale:** Tests that depend on RLS get the `postgres_only` pytest
  marker. CI runs both lanes; local dev still uses SQLite for speed.

## 3. Scope (3 tables, blast-radius ranked)

| Table | Tenancy column (after backfill) | Why first |
|-------|---------------------------------|-----------|
| `customer_audit_entries` | `tenant_id` (derived from `licenses.customer_email` → users.tenant_slug → email-domain heuristic) | KVKK / GDPR audit trail cross-leak |
| `webhook_events` | `tenant_id` (same chain, via `license_jti` → licenses → email) | Stripe payloads include PII + plan tier |
| `vault_audit_entries` | `tenant_id` (from `actor` email-domain heuristic; defaults `_unknown` then manual review) | Vault key rotations + access log |

Sprint 2L follow-up wave (9 tables): `licenses`, `data_export_jobs`,
`meetings`, `chat_sessions`, `chat_messages`, `tenant_invites`,
`tenant_installed_plugins`, `feature_usage_log`, `usage_log`.

## 4. FAZ Plan (this sprint)

| FAZ | Deliverable | ETA |
|-----|-------------|-----|
| A | Preflight + decision defaults (this doc) | 20 min |
| B | Alembic `0014_tenant_id_audit_tables` + `0014b_backfill_tenant_id` + 4 migration tests | 1 h |
| C | SQLAlchemy GUC listener + FastAPI tenant dep + Inngest wrapper + 6 unit tests | 1.5 h |
| D | Alembic `0015_rls_audit_tables` (ENABLE + FORCE RLS) + 5 postgres_only integration tests | 30 min |
| E | Alembic `0015b_abs_admin_role` + production deploy doc + 2 integration tests | 30 min |
| F | CI matrix postgres lane + `postgres_only` pytest marker | 30 min |
| G | RLS chaos test (drop GUC mid-request → 403) + `SPRINT_2K_RLS_CHAOS_TEST_LOG.md` | 30 min |
| H | `docs/security/multi-tenant.md` 3-layer defense + `threat-model.md` update | 20 min |
| I | `SPRINT_2K_REPORT.md` + `PRODUCTION_READY_CERTIFICATE_v1.0.0.md` Section IX footer + COMPLETE | 30 min |

## 5. Single-Actor Boundaries (Lesson 14)

This sprint ships **code + migration + tests + CI + docs only**. The
following remain founder actions and are explicitly outside worker scope:

- `v1.0.2` git tag + GitHub Release (Lesson 15-rev)
- `ALTER ROLE abs_admin GRANT TO postgres;` on the Hetzner production cluster
- Stripe / Resend live-mode promotion
- Pilot Batch 1 customer broadcast

The production deploy doc in FAZ E records the exact GRANT command so the
founder can run it once Iter-3 LIVE concludes.

## 6. Stop Criteria Watchlist

The brief lists 8 stop conditions. Active triggers monitored in real time:

1. Backfill `_unknown` row count > 5 % per target table → manual review,
   pause migration.
2. GUC listener `before_cursor_execute` p95 > 10 ms → optimize before merge.
3. Pytest count drops below 2126 (Sprint 2J baseline regression) → halt.
4. Chaos test surfaces 500 instead of 403 → FastAPI exception handler
   missing, fix before close.
5. Cerbos + RLS double-deny path test missing → add integration coverage.

If any trigger fires, the worker stops, captures the artefact under
`_agent-tasks/SPRINT_2K_STOP_*.md`, and waits for founder review.
