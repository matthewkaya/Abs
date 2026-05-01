"""Phase 3 — 25-case mock Anthropic + cascade fallback smoke.

Iterates 5 prompts × 5 mock modes (off=skipped, ok, rate_limit, timeout,
provider_500, random). Asserts:

* mode=ok      → mock returns echo, cascade primary works.
* mode=rate_limit / timeout / provider_500 → mock raises, cascade should
  surface fallback decision (we just verify the exception type — full
  cascade-with-Groq smoke is the operator's smoke runbook step).

Runs in-process so a Groq key is **not** required.
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

from app.providers.anthropic_mock import (
    AnthropicMockProvider,
    RateLimitError,
)
from app.providers.schemas import ProviderError


PROMPTS = [
    "Hello, summarize this document in one paragraph.",
    "Translate to Turkish: 'Welcome to ABS Server.'",
    "List the cascade providers in priority order.",
    "What is the difference between Coqui CPML and Piper MIT?",
    "Explain the 80/95 percent quota threshold to a new operator.",
]

MODES = ("ok", "rate_limit", "timeout", "provider_500", "random")


async def _run_one(mode: str, prompt: str) -> dict:
    provider = AnthropicMockProvider(behavior=mode)
    try:
        resp = await provider.complete(prompt, request_id=f"q3-{mode}-{len(prompt)}")
        return {"mode": mode, "verdict": "ok", "completion_prefix": resp.completion[:60], "tokens": resp.tokens}
    except RateLimitError as exc:
        return {"mode": mode, "verdict": "rate_limit", "exception": str(exc)}
    except TimeoutError as exc:
        return {"mode": mode, "verdict": "timeout", "exception": str(exc)}
    except ProviderError as exc:
        return {"mode": mode, "verdict": "provider_500", "exception": str(exc)}


async def main() -> int:
    results: list[dict] = []
    pass_ct = 0
    fail_ct = 0
    for mode in MODES:
        for prompt in PROMPTS:
            r = await _run_one(mode, prompt)
            results.append(r)
            # Acceptance per mode:
            #   ok           → verdict == 'ok'
            #   rate_limit   → verdict == 'rate_limit'
            #   timeout      → verdict == 'timeout'
            #   provider_500 → verdict == 'provider_500'
            #   random       → verdict in any of the four
            if mode == "random":
                ok = r["verdict"] in {"ok", "rate_limit", "timeout", "provider_500"}
            else:
                ok = r["verdict"] == mode
            if ok:
                pass_ct += 1
            else:
                fail_ct += 1
            print(f"  {'PASS' if ok else 'FAIL'}  mode={mode:<13} → {r['verdict']}")

    summary = {"pass": pass_ct, "fail": fail_ct, "results": results}
    Path("/tmp/anthropic_mock_results.json").write_text(json.dumps(summary, indent=2))
    print(f"\nPASS={pass_ct} FAIL={fail_ct}")
    return fail_ct


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
