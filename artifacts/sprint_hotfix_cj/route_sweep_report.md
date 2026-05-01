# Route Sweep Report — Sprint Hotfix CJ

**Run date:** 2026-04-29 (post-rebuild)
**Auth context:** panel session cookie of `admin@demo-acme.local` after setup completion
**Coverage:** 46 GET routes (no path params) discovered via `/openapi.json`

## Status distribution

| Status | Count | Notes |
|--------|-------|-------|
| 200 | 37 | All public + 8 admin + 4 marketplace + quota/changelog/signup |
| 401 | 4 | Auth-required without session: beta/queue, me/audit-log, me/consents, smart-link/connected-services |
| 422 | 5 | Required query/path params (BUG-CJ-013 backlog) — symbol-graph + email/unsubscribe + 2× smart-link callbacks |
| 5xx | **0** | Was 1 (`/v1/update/changelog` 503) pre-hotfix — closed by CJ-012 |
| 404 | 0 | Was 0 pre-hotfix; remains clean |

## Diff vs pre-hotfix sweep (`bugs.yaml::sweep_summary`)

| Metric | Pre | Post | Delta |
|--------|-----|------|-------|
| 200 | 25 | 37 | **+12** |
| 401 | 12 | 4 | **−8** |
| 422 | 5 | 5 | 0 |
| 503 | 1 | 0 | **−1** |
| 404 | 0 | 0 | 0 |

## 422 routes (carry-over BUG-CJ-013)

These return 422 because they require query / path / form params. Acceptable
behaviour but should be documented in OpenAPI schema with explicit `required: true`
parameter declarations. Tracked as low-severity backlog item.

```
/api/symbol-graph/neighbors        422   needs node_id query param
/api/symbol-graph/search           422   needs query string
/v1/email/unsubscribe              422   needs token param
/v1/smart-link/github/callback     422   OAuth callback, needs code+state
/v1/smart-link/slack/callback      422   OAuth callback, needs code+state
```

## 401 routes (auth-only, expected)

```
/v1/admin/beta/queue                401   beta-admin scope (separate from panel admin)
/v1/me/audit-log                    401   tenant scope (no JWT in this sweep)
/v1/me/consents                     401   tenant scope
/v1/smart-link/connected-services   401   tenant scope
```

These are expected to gate behind tenant JWT (T-005 MCP gateway flow), not
panel admin session.

## Acceptance gate

- 0 × 5xx ✅
- 0 × 404 ✅
- 200-coverage rose from 54% → 80% of GET routes
- All 8 `/v1/admin/*` cookie-auth endpoints now 200 (CJ-010)
