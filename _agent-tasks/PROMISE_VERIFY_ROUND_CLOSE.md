# Worker — Promise Verify round close (R1..R6)

> Branch: `feat/sprint-q12-deep-quality`
> Baseline (HEAD pre-round): 1791 PASS / 0 FAIL / 0 ERROR (post-Round-6 BUG-12).
> Founder audit gap: PROMISE.md vow had 6/11 unverified items.

## R1 — `/admin/usage` widget (BUG-V1 HIGH)

- Backend: `core/backend/app/api/admin/usage.py` — new `GET /v1/admin/usage` (admin-gated, single-source-of-truth aggregate of `quota_monitor.status()` + `rag_usage.jsonl`). Returns `claude.used_pct`, `free_path.pct_24h`, `paid_path.calls_24h`, `provider_mix_24h`, dense 7-day trend.
- Frontend: `core/landing/app/admin/usage/page.tsx` (server-shell + cookie forward) + `UsageClient.tsx` (Tremor metric tiles + AreaChart).
- Sidebar: added `/admin/usage` "Kullanım" entry under Üretim group.
- Tests: `tests/test_promise_v1_admin_usage.py` — 3 (auth gate, cold install, 24h aggregation).

## R2 — Workflow USD cost estimate (BUG-V2 HIGH)

- `app/workflow_v10/runner.py` — new `estimate_cost(plan_steps)` with `_FREE_PROVIDERS` short-circuit + per-call USD table for paid providers (haiku/sonnet/opus/openai). `plan()` now carries the source `node` so cost lookup uses provider/model config without re-walking.
- `app/api/workflows.py` — `/v1/workflows/execute` response carries `estimated_cost_usd` for both `dry_run` and `queued` branches; embedded `node` is stripped from the public `steps` shape.
- Tests: `tests/test_promise_v2_workflow_usd_estimate.py` — 2 (free-tier only ⇒ $0.0; anthropic node ⇒ > $0).

## R3 — Opt-in flip + quota-block audit emit (BUG-V3 MED)

- `app/observability/optin_state.py` — new `detect_and_emit_flip()` boot-time helper: reads/writes `data/last_optin_state.json`, emits `settings.optin.flip` action via `emit_event` when current `anthropic_enabled` differs from the stored snapshot. First-boot writes only; no false positives.
- `app/main.py` lifespan — wires `detect_and_emit_flip(current_enabled=settings.anthropic_enabled)` after vault boot.
- `app/observability/quota_monitor.py` `gate()` — emits `quota.block` (outcome=denied, provider=anthropic) before raising `QuotaExceeded`. Audit failures swallowed so the gate stays operational.
- Tests: `tests/test_promise_v3_audit_optin_quota.py` — 3 (first-boot quiet, true-flip emits row, gate emits on raise).

## R4 — Sprint 13 win-rate eval (BUG-V4 HIGH, evidence run)

- Dataset: `core/backend/tests/fixtures/golden_eval_multimodel.json` — 30 prompts (10 code / 10 analysis / 10 translation) with `expected_traits` for the LLM-judge.
- Harness: `scripts/eval/multimodel_winrate.py` — uses `httpx` (avoids macOS bare-Python SSL trust issue), calls Groq GPT-OSS-120B and Anthropic Claude Opus per row, judges with Groq Llama 3.3 70B, aggregates `(gpt_oss_wins + 0.5 * tie) / contested`. Honest gating: missing `ANTHROPIC_API_KEY` ⇒ verdict `claude_unavailable`, win-rate reported as `unmeasured`.
- **Live run (2026-05-06):** GPT-OSS-120B answered 10/30 rows before the Groq free-tier 429 rate-limit; Claude side **not run** (no key in this env). Artifact: `artifacts/promise_verify/sprint_13_winrate.md` + `.json`. Win-rate: **unmeasured** — PROMISE.md updated to reflect this honest state instead of restating the unverified 50 % claim.
- Tests: `tests/test_promise_v4_winrate_harness.py` — 4 (dataset balance, aggregate-no-contest = None, win-rate math, offline-mode artifact write).

## R5 — LangFuse `claude_tokens_used_pct_month` wired (BUG-V5 MED)

- `app/observability/quota_monitor.py` — `record()` now calls `_push_langfuse_pct(s)` after appending the ledger row. Helper imports langfuse_client lazily, checks `is_enabled()`, calls `client.score(name="claude_tokens_used_pct_month", value=used_pct, ...)`. Failures swallowed.
- Tests: `tests/test_promise_v5_langfuse_quota_score.py` — 3 (enabled ⇒ exactly one score, disabled ⇒ no scores, broken SDK ⇒ record() still succeeds).

## R6 — `docs/ABS_HYBRID_TIER_PROMISE.md` honest revision

- v1.0 → v1.1 (2026-05-06).
- "Quality bar" section rewritten: replaces fabricated "Sprint 13 verified ≥ 50 % win-rate" with the dataset/harness/artifact path tuple plus an explicit "win-rate: unmeasured (no Anthropic key in last run)" disclosure.
- "What the customer sees" bullets now name the actual files behind each vow (`page.tsx`, `runner.py.estimate_cost`, `quota_monitor.gate`, `optin_state.detect_and_emit_flip`) so the next audit can follow the source links.

## Verification

- New tests: 15 (V1×3, V2×2, V3×3, V4×4, V5×3) — every harness gate plus the live-vs-cold paths.
- pytest baseline 1791 → expected 1806 after merge (1791 + 15).
- Full suite gate command (re-run pre-merge):
  ```
  cd core/backend && ./.venv/bin/python -m pytest --no-header -q \
    --ignore=tests/test_providers.py \
    --ignore=tests/test_q03_real_saas_backends.py \
    --ignore=tests/test_update_channel.py
  ```
- Image rebuild required before live curl probes against `/v1/admin/usage` and `/v1/workflows/execute` (backend changes).
- `live_path_verified`: `GET /v1/admin/usage` returns shape `{month, claude:{used_pct,banner}, free_path:{pct_24h}, paid_path, daily_trend[7]}` — confirmed via pytest contract; live curl pending image rebuild.

## Honest status of the founder audit

| PROMISE.md vow | Pre-round | Post-round |
|---|---|---|
| Free path % widget | absent | live (`/admin/usage`) |
| Claude budget % widget | absent | live (`/admin/usage`) |
| 7-day token trend chart | absent | live (Tremor AreaChart) |
| Workflow `Estimated cost per run` | only `estimate_s` | `estimated_cost_usd` field |
| Opt-in flip audit emit | absent | live (boot-time detector) |
| Quota-block audit emit | log-only | `abs.audit` row on every gate raise |
| LangFuse `claude_tokens_used_pct_month` | implicit | explicit `score()` call |
| Sprint 13 ≥50 % win-rate | unverifiable claim | falsifiable harness, latest run = **unmeasured** (no Claude key) |

PROMISE.md now reflects the verifiable state. Win-rate target is documented as aspirational pending an operator's live run with both keys.
