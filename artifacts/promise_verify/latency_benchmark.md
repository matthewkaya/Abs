# Latency benchmark — Groq vs Anthropic

> Generated: 2026-05-07T10:40:02+00:00 · mode: `live-no-anthropic` · duration: 507.7s
> Dataset: `core/backend/tests/fixtures/golden_eval_multimodel.json` (100 prompts)
> Groq model: `openai/gpt-oss-120b`
> Anthropic model: `claude-sonnet-4-5-20250929`

## Wall-clock latency

| Provider | n_ok | errors | P50 (ms) | P95 (ms) | mean (ms) | stdev (ms) |
|---|---|---|---|---|---|---|
| Groq GPT-OSS-120B | 100 | 0 | 5829.2 | 7312.3 | 5076.1 | 2277.3 |
| Anthropic Sonnet 4.5 | 0 | 100 | None | None | None | None |

## Speedup (Anthropic / Groq)

_Speedup unmeasured — one provider returned zero successful samples (typical when `ANTHROPIC_API_KEY` is not set)._

## Token usage (sum across all prompts)

| Provider | Input tokens | Output tokens |
|---|---|---|
| Groq | 14462 | 56458 |
| Anthropic | 0 | 0 |

## Notes

- Wall-clock timing uses `time.perf_counter()` around each HTTP POST, including TLS handshake — that is the customer-felt latency.
- `AnthropicThrottle` (≤30 calls / 15-min) is honoured to keep the Plus tier within budget during the run.
- No LLM-as-judge is invoked; this script makes no claim about output quality. See `cost_ledger.md` and `cascade_smoke.md` for the other two empirical promises.

## Reproduce

```bash
export GROQ_API_KEY=...
export ANTHROPIC_API_KEY=...    # optional, opt-in only
python scripts/eval/latency_benchmark.py
```
