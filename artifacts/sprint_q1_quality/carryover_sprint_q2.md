# Sprint Q2 Quality Carry-over Brief (Draft)

> **Trigger:** Sprint Q1 closed 2026-04-29 with 9 ✅ + 3 ⚠️. Three deferred items + four real-API-key personas + two HITL studies need a follow-on sprint.

## Q2.CO1 — UsageLog model + cascade-call instrumentation
**Why:** A7 threshold trigger was PARTIAL — `_query_usage_sum()` returns 0 because no `UsageLog` SQLModel exists yet. Threshold helper logic is verified, but live 80%/95% warning never fires from real traffic.
**Scope:**
- Add `UsageLog(provider:str, tokens:int, cost_usd:float, ts:datetime)` SQLModel.
- Alembic 0005 migration (mirror feature_usage_log shape).
- Wire each cascade provider call (`app.providers.cascade.*`) to `UsageLog.append`.
- A7 retest: seed 850K events for `anthropic` → `quota_status.warnings == ['claude_plus_warning_80']`.

## Q2.CO2 — Tenant JWT mint helper for RAG harness
**Why:** A9 only verified the auth gate (`401 missing_bearer_token`). Full corpus ingest + golden top-1 retrieval requires a tenant-scoped JWT, which the test harness does not produce today.
**Scope:**
- `tests/util/mint_tenant_jwt.py` helper using OAuth client-credentials flow.
- Live ingest 5 corpus docs from `golden_eval_dataset.json` for tenant-acme.
- Live query → top-1 doc_id == `acme-billing-faq`.
- Optional: ship pytest in a sidecar test-only image so the same suite runs against the running container.

## Q2.CO3 — Real Q-A golden dataset (50+ pairs)
**Why:** B4 RAGAS answer_relevance 0.157 — fallback samples used `answer = full context`, not the actual answer to the question. Mock backend rates relevance by question↔answer token overlap; needs real Q-A pairs.
**Scope:**
- 50+ Q-A pairs covering ABS docs (setup, marketplace, RAG, meetings, quota).
- Format compatible with existing `EvalSample` dataclass (question, answer, contexts, ground_truth).
- Re-run B4 → answer_relevance ≥ 0.65.

## Q2.CO4 — Real ragas backend wiring (LLM-judge)
**Why:** Mock backend uses token-overlap heuristic. Production-grade evaluation needs an LLM judge (the actual `ragas` package) for faithfulness + answer_relevance.
**Scope:**
- Pip-install `ragas` in backend image (already deferred-import in `ragas_eval.py`).
- Provide ABS_RAGAS_LLM_KEY (Anthropic or OpenAI) via vault.
- Toggle backend via `settings.ragas_backend = "real" | "mock"`.
- Compare mock vs real on the same 50-sample dataset; quantify drift.

## Q2.CO5 — Persona A1: signup + magic-link claim
**Why:** `/auth/signup` accepts pending tenants, but no claim flow promotes them to admin.
**Scope:**
- `magic_token` -> `tenants_pending` row -> claim endpoint that consumes token + creates `User`.
- Multi-admin DB schema (extend `admin_credentials.json` to a SQLModel `User` table).
- A1 test: signup → claim → login → admin endpoint access.

## Q2.CO6 — Persona A4: paid-tier with Anthropic key + cascade fallback
**Why:** Free-tier verified end-to-end; paid-tier (with Anthropic key) only verified via setup form.
**Scope:**
- Provision an Anthropic API key (operator-supplied, vault-scoped).
- Smoke `/v1/cascade/run` with prompt that should hit Anthropic primary, fall back to Groq on rate limit.
- Verify `feature_usage.cascade_provider_call` increments per provider hit.

## Q2.CO7 — Persona A10: NL → workflow → execute
**Why:** Sprint 19 T-S03 shipped NL→JSON synthesizer at the module level, but no end-to-end persona test.
**Scope:**
- Live `POST /v1/workflows/synthesize` with NL prompt → JSON workflow.
- Validate workflow against n8n schema.
- Execute via `WorkflowExecutor.run`; assert HITL gate fires for `hitl` node kinds.

## Q2.CO8 — HITL persona D1 (TTS naturalness) + D2 (UI usability)
**Why:** Cannot automate. Subjective scores deferred but worth scheduling.
**Scope:**
- D1: 3 listeners × 3 voices × 5 sample texts → MOS 1-5. Target: mean MOS ≥ 3.5.
- D2: 3 users × 5 tasks (signup, setup, marketplace install, meeting upload, quota check) → time-on-task + completion rate. Target: ≥ 4/5 tasks completed without help.
- Schedule via Calendly/Google Form; budget 2 hours per session.

---

## Estimated effort

| Track | Hours |
|-------|-------|
| Q2.CO1 (UsageLog) | 4 |
| Q2.CO2 (RAG harness) | 5 |
| Q2.CO3 (Q-A dataset) | 3 (mostly content) |
| Q2.CO4 (real ragas) | 6 (LLM costs apply) |
| Q2.CO5 (signup claim) | 8 (multi-admin DB schema) |
| Q2.CO6 (paid-tier) | 4 |
| Q2.CO7 (workflow) | 6 |
| Q2.CO8 (HITL) | 6 (scheduling + facilitation) |
| **Total** | **42 h** (~5-6 worker-days serial; ~2 days with parallel split) |
