"""Phase 11 — degradation matrix runner (in-process, no pytest).

Iterates `cascade_degradation_matrix.json` 7 scenarios, mutates settings
attributes for the missing providers, and asserts `get_active_providers`
returns the expected chain.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from app.config import settings
from app.providers.cascade import (
    PROVIDER_ORDER,
    SETTINGS_KEY_ATTR,
    get_active_providers,
)


# Seed every provider with a plausible-looking dev key so baseline =
# all configured. Tests then strip the missing ones.
DEV_KEYS = {
    "anthropic": "sk-ant-test-1234567890abcdef",
    "groq": "gsk_test_1234567890abcdef",
    "cerebras": "csk-test-1234567890abcdef",
    "gemini": "AIza-test-1234567890abcdef",
    "cloudflare": "cfp_test_1234567890abcdef",
    "cohere": "co_test_1234567890abcdef",
}


def _seed_baseline() -> dict[str, str]:
    """Set every provider key to a dev-grade value, return the previous
    values so we can restore."""
    backup: dict[str, str] = {}
    for prov in PROVIDER_ORDER:
        attr = SETTINGS_KEY_ATTR[prov]
        backup[attr] = getattr(settings, attr, "")
        setattr(settings, attr, DEV_KEYS[prov])
    return backup


def _restore(backup: dict[str, str]) -> None:
    for attr, value in backup.items():
        setattr(settings, attr, value)


def _strip(missing: list[str]) -> None:
    for prov in missing:
        attr = SETTINGS_KEY_ATTR[prov]
        setattr(settings, attr, "")


def main() -> int:
    fixture = json.loads(
        Path("/app/tests/fixtures/cascade_degradation_matrix.json").read_text()
    )
    pass_ct = 0
    fail_ct = 0
    results: list[dict] = []
    for scenario in fixture:
        backup = _seed_baseline()
        try:
            _strip(scenario["missing"])
            chain = get_active_providers()
            actual_len = len(chain)
            actual_primary = chain[0] if chain else None

            ok = actual_len == scenario["expected_chain_length"]
            if "expected_primary" in scenario:
                ok = ok and actual_primary == scenario["expected_primary"]
            if scenario.get("expected_error"):
                ok = ok and actual_len == 0  # 503 trigger condition
            verdict = "PASS" if ok else "FAIL"
            (pass_ct if ok else fail_ct).__class__  # noqa - placate mypy
            if ok:
                pass_ct += 1
            else:
                fail_ct += 1
            results.append(
                {
                    "scenario": scenario["name"],
                    "expected_chain_length": scenario["expected_chain_length"],
                    "actual_chain_length": actual_len,
                    "expected_primary": scenario.get("expected_primary"),
                    "actual_primary": actual_primary,
                    "verdict": verdict,
                }
            )
            print(
                f"  {verdict}  {scenario['name']:<32} "
                f"chain={actual_len} primary={actual_primary}"
            )
        finally:
            _restore(backup)

    summary = {"pass": pass_ct, "fail": fail_ct, "results": results}
    Path("/tmp/matrix_results.json").write_text(json.dumps(summary, indent=2))
    print(f"\nPASS={pass_ct} FAIL={fail_ct}")
    return fail_ct


if __name__ == "__main__":
    sys.exit(main())
