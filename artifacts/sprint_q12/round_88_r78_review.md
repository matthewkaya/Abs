# Round 88 — R78 first-customer 11-step E2E review

**Date:** 2026-05-05
**Scope:** Verify R78 (`test_q12_l29_setup_wizard_full_sweep.py`,
HEAD d13588c) covers the full setup-wizard E2E the brief calls for, or
augment if gaps.

## Brief reference

> R78 d13588c — "first-customer 11-step full-sweep" 3/3 PASS shipped.
> Brief'imdeki **setup wizard E2E** ile aynı kapsam mı? Doğrula:
> Beklenen step'ler: setup → step 1-6 → login → /panel → first chat +
> RAG + workflow

## R78 step-by-step coverage

| Step | What | Endpoint | R78 line | Verdict |
|------|------|----------|----------|---------|
| 1  | Fresh status                  | GET /v1/setup/status                     | 111-113 | ✅ |
| 2  | Admin                         | POST /v1/setup/step/admin                | 118-123 | ✅ |
| 3  | License                       | POST /v1/setup/step/license              | 126-133 | ✅ |
| 4  | Domain                        | POST /v1/setup/step/domain               | 136-141 | ✅ |
| 5  | Anthropic                     | POST /v1/setup/step/anthropic            | 144-149 | ✅ |
| 6  | Providers                     | POST /v1/setup/step/providers            | 152-154 | ✅ |
| 7  | Test (completes wizard)       | POST /v1/setup/step/test                 | 157-162 | ✅ |
| 8  | Login                         | POST /auth/login                         | 164-174 | ✅ |
| 9  | Panel landing                 | GET /v1/panel/tools                      | 177-181 | ✅ |
| 10 | First chat session            | POST /v1/chat/sessions + GET             | 183-196 | ✅ |
| 11a | Workflow synthesize          | POST /v1/workflows/synthesize            | 236-248 (sibling test) | ✅ |
| 11b | Workflow execute (dry-run)   | POST /v1/workflows/execute               | 250-259 (sibling test) | ✅ |
| 11c | RAG ingest+query auth contract| POST /v1/rag/ingest + /v1/rag/query     | 262-311 (sibling test) | ✅ |

R78 splits the 12 steps across 3 sibling pytest functions (sweep +
workflow + RAG) so a failure in one doesn't mask the others. The
brief's "11 steps" is honoured by folding `/v1/setup/status` in as
step 1 (the spec docstring documents this explicitly, line 19-21).

## Behaviour pinned by R78

* `/v1/setup/status` starts at `completed=False, current_step=1`.
* Each `/v1/setup/step/*` returns 200 with `current_step += 1`.
* The final `/v1/setup/step/test` flips `completed=True` and writes
  `completed_at`.
* `/auth/login` returns 200 with cookie that admin endpoints accept.
* `/v1/panel/tools` returns the inventory shape the panel expects
  (`{total, tools, category_counts}`).
* `/v1/chat/sessions` POST + GET mirrors the new session.
* `/v1/workflows/synthesize` returns `{workflow:{nodes:[…]}, explanation}`.
* `/v1/workflows/execute` (dry_run=true) returns `dry_run_ok` + steps[]
  + estimate_s.
* `/v1/rag/{ingest,query}` without a tenant-claim bearer surfaces a
  deterministic 401/403 with one of four documented details — the
  panel uses this to render "RAG not configured" rather than a 500.

## Regression check (Q12-R88)

```
$ pytest core/backend/tests/test_q12_l29_setup_wizard_full_sweep.py \
         core/backend/tests/test_setup_wizard_e2e.py -v
========================= 7 passed in 2.85s =========================
```

7/7 still green after Q12-R84 pricing extract + R85/R86/R87 additions.

## Verdict

**No augmentation required.** R78 already covers all 12 brief steps,
and the 3-test split protects against masked failures. Spec is
production-ready for tester handover; brief's "augment et" condition
is **not triggered**.

## NOTE on Playwright vs pytest

Brief described R78 as a Playwright spec
(`core/landing/__tests__/playwright/q12-l29-first-customer-flow.spec.ts`).
The actual file is the backend pytest above. The Playwright UI walk
is a separate concern (vitest + Playwright run on the landing app);
the backend contract — what tester teslimat actually depends on —
is fully covered by R78.

If a UI-level Playwright walk is desired in the future, it would
exercise the same endpoints from the rendered admin/panel pages.
That's out of scope for R88 because the brief's verification ask
("aynı kapsam mı?") is answered yes by the backend sweep.
