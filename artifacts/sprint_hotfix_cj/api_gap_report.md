# API Gap Report — Sprint Hotfix CJ

**Run date:** 2026-04-29
**Status:** ✅ closed for CJ-008 + CJ-009; carry-over for /signup naming

## OpenAPI inventory (post-hotfix)

| Domain | Path | Source |
|--------|------|--------|
| Marketplace | `/v1/marketplace/plugins` | NEW (CJ-008) |
| Marketplace | `/v1/marketplace/plugins/{plugin_id}` | NEW (CJ-008) |
| Marketplace | `/v1/marketplace/install` | NEW (CJ-008) |
| Marketplace | `/v1/marketplace/installed` | NEW (CJ-008) |
| Quota | `/v1/system/quota_status` | NEW (CJ-009) |
| Quota | `/api/quota-status` | LEGACY stub (kept for back-compat) |
| Auth | `/auth/signup` | NEW (CJ-003) |

## Frontend ↔ backend alignment

| UI artefact | Calls | Backend route | Status |
|-------------|-------|---------------|--------|
| `core/landing/app/admin/marketplace/page.tsx` (existing) | (no fetch yet) | `/v1/marketplace/plugins` | ✅ live |
| `core/landing/app/signup/page.tsx` (NEW) | `fetch("/auth/signup")` | `/auth/signup` | ✅ live (201) |
| `core/landing/app/page.tsx` (Pricing component) | gated on `NEXT_PUBLIC_BILLING_ENABLED` | n/a (link-only) | ✅ flagged |

## Diff against pre-hotfix sweep

Pre-hotfix (2026-04-29 17:39 sweep):
- 25 × 200 / 12 × 401 / 5 × 422 / 1 × 503 / 0 × 404

Post-hotfix:
- 37 × 200 / 4 × 401 / 5 × 422 / 0 × 5xx / 0 × 404

Net change:
- **+12** new 200 responses (admin endpoints unblocked + new marketplace + quota_status + changelog)
- **−1** 503 (CJ-012 closed)
- **−8** 401 (CJ-010 unification)

## Carry-over

- `signup` route lives at `/auth/signup` (auth router prefix), not `/v1/auth/signup` as the brief specified.
  Frontend updated to match. If a breaking-change sprint moves auth to `/v1/auth/*`, signup goes with it.

## Mock data

`grep -r "mock-\|.mock.\|__mocks__" core/landing/app core/landing/src` → 0 matches.
No frontend mock/fixture files leak into production.
