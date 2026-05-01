# Phase 7 — Groq qwen32b RAGAS judge drift report

**Status:** module shipped, live judge requires operator-supplied Groq key.

## Module
`core/backend/app/observability/ragas_groq.py` (NEW, 168 LOC).
Drop-in for `_MockBackend.evaluate(samples) → EvalScores`. Concurrency-bounded
(default 4) so a 50-sample batch fits Groq free TPM. Model defaults to
`qwen/qwen3-32b` (override via `ABS_RAGAS_GROQ_MODEL`).

## Live judge — operator step
Set `ABS_GROQ_API_KEY` in backend env, then:

```bash
docker exec abs-cj-backend-1 python3 -c "
from app.observability.ragas_groq import get_groq_evaluator
from app.observability.ragas_eval import EvalSample
import json
ds = json.load(open('/app/tests/fixtures/golden_qa_50.json'))
samples = [EvalSample(question=e['question'], answer=e['answer'], contexts=e['contexts'], ground_truth=e['ground_truth']) for e in ds]
scores = get_groq_evaluator().evaluate(samples)
print(scores)"
```

## Mock baseline (Q1+Q2)
- faithfulness: 0.4245
- answer_relevance: 0.358
- context_precision: 0.04
- context_recall: 0.5569

## Expected delta (real LLM judge)
qwen-2.5-32b judge should rate **answer_relevance >= 0.65** (the Q-A pairs
answer their questions correctly; the mock under-scores due to token-overlap
sensitivity to paraphrase). `faithfulness` and `context_precision` should
also rise as the judge accepts semantically grounded paraphrase rather than
demanding exact token overlap.

## Carry-over to Q4
Operator vault step: `vault put secret/abs/groq_api_key value=gsk_...`.
Then this module runs head-to-head against `_MockBackend`; drift report
quantifies the lift.
