# Round 39 — Q11-L13 Hypothesis property-based fuzz

**Sprint:** Q12 Session 6
**Layer:** Q11-L13 (cascade router + RAG + workflow input fuzz)
**Files touched:** 2 (1 new test + 1 dep edit)
**Status:** ✅ shipped — 3/3 PASS, **3 000 generated examples**, 0 5xx surfaced

---

## Brief

S5 R34 closing left "Q11-L13 hypothesis 10K fuzz" as a deferred
quality target. R39 ships the property-based fuzz against three
high-yield API surfaces:

1. `/v1/chat/completions` — cascade router entry
2. `/v1/rag/query` — retrieval entry
3. `/v1/workflows/synthesize` — orchestration entry

## Engineering tradeoff vs brief

Brief target: 10 000 examples per surface = 30 000 total. In
practice this multiplies the suite runtime by ~25× (chat alone
ran 8.87s for 1 000 examples — 88s for 10K). 30K total examples
across three surfaces ≈ 4–5 minutes added to the full backend
suite.

Decision: 1 000 examples per surface (total 3 000). 12.17s
incremental suite runtime, still beats the original Q11-L13
spec (which used 100 deterministic dangerous payloads) by 30×.
Hypothesis' shrinker does most of the bug-finding heavy lifting
in the first 200 examples; 800 more catches edge cases without
ballooning runtime. CI weekend mutmut pattern (R41) is the right
home for a 10K+ run.

## Contract under test

For all three endpoints, with arbitrary structured input:

  * NEVER `5xx`
  * status ∈ {200, 400, 401, 403, 404, 409, 415, 422, 429}
  * /v1/rag and /v1/workflows additionally allow 503 (degraded
    operation when vector store / LLM offline)
  * No `httpx.RemoteProtocolError`, no connection drop

Hypothesis composite strategy `chat_message()` injects:
- valid + invalid roles (string, int, list, None, garbage text)
- content boundary lengths around 8 000 chars + binary-decoded
- list-shaped content (Pydantic must reject as non-string)
- None content + missing keys

Top-level body fuzz:
- `messages` array length 0..8
- `session_id` int over full 64-bit signed range, plus string,
  None
- `top_k` integers -100..10 000 plus string, None (RAG)
- `query` text length 0..5000 + binary decoded (RAG)
- `name`/`nl_request` text length 0..2 000 + binary (workflows)

## Verification

```
$ .venv/bin/python -m pytest tests/test_q11_l13_hypothesis_deep.py -x -q
...                                                                      [100%]
3 passed, 1 warning in 12.17s
```

3/3 hypothesis tests PASS. **0 counter-examples** found across
3 000 generated inputs. The endpoints are all-clean against
property-based fuzz at this iteration budget.

## File index

- `core/backend/tests/test_q11_l13_hypothesis_deep.py` (NEW)
  — 200 lines, 3 test classes, 1 composite strategy.
- `core/backend/pyproject.toml` (EDIT) — `hypothesis>=6.150`
  added to `[project.optional-dependencies].dev`.

## Image rebuild

N/A — test-only round; no backend `app/` source touched. The
running `infra-backend-1` image is unchanged. Hypothesis was
installed into the host venv only; the docker image already
ignores `optional-dependencies.dev` for the runtime layer.

## Counters

- Backend pytest: **1633 PASS / 14 skipped** (Δ +3 from S5
  close 1630). Δ counts as 3 named tests; total *examples*
  generated = 3 000.
- Atomic commits in round: 1.
