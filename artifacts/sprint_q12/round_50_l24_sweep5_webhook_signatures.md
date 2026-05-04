# Round 50 — L24 sweep 5: webhook signature secret audit

**Sprint:** Q12 Session 7
**Layer:** L24 (secret leakage / ops visibility) — sweep 5
**Files touched:** 2 src + 1 new test
**Status:** ✅ shipped — **Q12-L24-008 (LOW) closed**, 13/13 tests PASS

---

## Audit findings

| Webhook | Pre-R50 state | Finding |
|---------|---------------|---------|
| Stripe (`/v1/webhooks/stripe`) | Sweep 2 emit_event coverage already in place — `signature_missing`, `payload_invalid`, `signature_invalid` (with `error_class`). | Clean. R50 adds source-grep regression pin. |
| Slack (`/v1/integrations/slack/webhook`) | `verify_slack_signature` returned `(ok, reason)` tuple; caller routed reason into emit. Coverage clean since sweep 2. | Clean. R50 adds regression pin. |
| **GitHub (`/v1/integrations/github/webhook`)** | `verify_webhook_signature` returned **single bool**. Caller emitted `reason="signature_invalid"` for **all** failure modes — including the boot misconfig case where `secret == ""`. | **Q12-L24-008 (LOW ops visibility)** — operations cannot distinguish "we forgot to provision GITHUB_APP_WEBHOOK_SECRET" from "an attacker is probing the endpoint." |
| Inngest | Signature verification delegated to inngest SDK `fast_api.serve(app, client, functions)`. Not a user-facing webhook surface we own. | No fix surface. |

## Q12-L24-008 fix

### `core/backend/app/integrations/github_app.py` (EDIT)

Added `verify_webhook_signature_typed(secret, body, signature_header)
-> (ok: bool, reason: str)`. Reason taxonomy:

| reason | meaning | ops action |
|--------|---------|-----------|
| `""` | ok=True | success path |
| `signing_secret_empty` | backend not provisioned | **rotate/install secret** — not an attack |
| `header_missing` | request lacked `X-Hub-Signature-256` or wrong prefix | could be misconfigured webhook URL or scanner; review traffic |
| `signature_mismatch` | header well-formed but HMAC didn't match | **attack signal** — likely probing the endpoint |

The legacy single-bool `verify_webhook_signature` is now a
back-compat shim that delegates to the typed impl + drops the
reason. External callers (none currently in-repo besides the
router we just updated) keep working unchanged.

### `core/backend/app/api/integrations/github_app.py` (EDIT)

Switched the webhook handler to `verify_webhook_signature_typed`
and routes the typed `reason` into `emit_event(...)`:

```python
ok, reason = verify_webhook_signature_typed(...)
if not ok:
    emit_event(
        request,
        action="integrations.github.webhook.signature",
        outcome="denied",
        reason=reason or "signature_invalid",
        ...
    )
    raise HTTPException(401, "GitHub signature verification failed")
```

Response body stays generic ("GitHub signature verification
failed") — the audit channel carries the taxonomy. No info leaks
to the caller about which check failed.

### `core/backend/tests/test_q12_l24_sweep5_webhook_signatures.py` (NEW)

13 tests:

- 5 typed-helper unit tests: `signing_secret_empty`,
  `header_missing` (× 2 — empty + wrong prefix),
  `signature_mismatch`, ok-path
- 2 back-compat shim tests
- 2 router-side regression tests (uses typed helper, routes
  reason into emit)
- 3 Stripe webhook source-grep pins (signature_missing /
  payload_invalid / signature_invalid)
- 1 Slack webhook source-grep pin (uses typed helper + routes
  reason)

## Verification

```
$ pytest tests/test_q12_l24_sweep5_webhook_signatures.py -v
13 passed in 0.49s
```

Existing webhook integration tests (Slack/GitHub/Stripe) still
pass — the back-compat shim preserves the old API.

## Image rebuild

⚠️ Backend `app/` source touched. Conditional rebuild gate fires
when this and R49 ship to a deploy. The host venv pytest verifies
correctness; image rebuild is batched with R49.

## Layer matrix delta

| Layer | Before R50 | After R50 |
|-------|------------|-----------|
| L24 | 4/3 ⭐ deep (R14+R18+R22+R25+R29) | **5/3 ⭐ deep round 5** (+ R50 webhook signature ops-taxonomy) |

Q12-L24-008 (LOW ops visibility) closed.

## Counters

- Backend pytest: 1652 → **1665 PASS** (Δ +13) / 14 skipped.
- Atomic commits in round: 1.
- Bugs closed: 1 (Q12-L24-008 LOW).
