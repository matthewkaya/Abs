# Round 22 — L24 sweep 2 webhook signature audit + leak hardening

**Sprint:** Q12 Session 3
**Layer:** L24 (secret/sensitive leakage scan) — sweep 2
**Files touched:** 3 src + 1 new test
**Status:** ✅ shipped

---

## Real bugs surfaced

### Q12-L24-003 (MED security info-leak) — Slack webhook reveals signing-check internals

`POST /v1/integrations/slack/webhook` failed-verify response body
contained the full reason taxonomy from `verify_slack_signature`:

```
"Slack signature verify failed: {reason}"
  reason ∈ {
    signing_secret_empty,   # boot misconfig signal
    header_missing,         # header probing signal
    timestamp_invalid,      # replay-window probing
    timestamp_expired,      # 5min window distance signal
    signature_mismatch,     # secret-fingerprint signal
  }
```

An unauthenticated caller can hammer the endpoint and learn:
1. **Boot state** — `signing_secret_empty` confirms `SLACK_SIGNING_SECRET`
   isn't provisioned.
2. **Replay tuning** — `timestamp_expired` vs `signature_mismatch` lets
   an attacker know whether the 5-min replay window vs the HMAC is the
   gating check. Useful when iterating stolen payload + forged sig.
3. **Header-probe vs invalid-format** — distinguishing
   `header_missing` from `timestamp_invalid` from `signature_mismatch`
   tells which header the receiver actually parses.

Same Q12-L24 family as the R14 Stripe `str(exc)` leak (cus_*/sub_*
IDs into checkout/billing detail).

**Fix:** route the reason taxonomy to the audit channel; return
generic `"slack_signature_invalid"` (HTTP 401) regardless of which
sub-check failed.

### Q12-L24-004 (LOW operability) — All 3 webhook signature paths silent in audit

Pre-Round 22, none of the three webhook receivers
(`/webhooks/stripe`, `/v1/integrations/slack/webhook`,
`/v1/integrations/github/webhook`) emitted an audit event on signature
or payload denial. Slack had a `logger.warning("[slack] webhook
rejected: %s", reason)` but no structured `abs.audit` line. Stripe
had nothing. GitHub had nothing.

Operationally this is the *most attractive* attack surface on the
public ingress: anyone on the internet can hit it; the only defence is
the HMAC. Without structured audit, ops cannot graph webhook-signature
denial rates, alert on a sudden spike (credential probing), or
correlate to an account/IP.

**Fix:** wire `emit_event` on every signature/payload denial across
the 3 receivers:

```
webhooks.stripe.signature              denied {signature_missing | signature_invalid}
webhooks.stripe.payload                denied payload_invalid (ValueError)
integrations.slack.webhook.signature   denied {<reason taxonomy>}
integrations.slack.webhook.payload     denied invalid_json
integrations.github.webhook.signature  denied signature_invalid
integrations.github.webhook.payload    denied invalid_json
```

`error_class=type(exc).__name__` carries the SDK-side discriminator
(SignatureVerificationError vs ValueError) into audit without leaking
exception text into the response body.

---

## Contract / regression guard test

`test_slack_response_body_does_not_leak_reason_taxonomy` asserts that
*every* Q12-L24-003 reason token is absent from the response body
text. If a future maintainer reverts `f"Slack signature verify
failed: {reason}"`, the test fails immediately. Same pattern as the
R14 Stripe response-body assertions for cus_/sub_/acct_ tokens.

`test_stripe_signature_invalid_emits_denied` and
`test_stripe_payload_invalid_emits_denied` similarly assert that
SDK exception strings ("No signatures found...", "Could not
deserialize key data...") never reach the response body.

---

## Image + container evidence

```
image_rebuilt_at: 2026-05-03T14:29:xx (Q12 Session 3 third rebuild)
container_pytest_pass: 28/28 (R22 sweep2 + 028 webhook regression)
```

Live container smoke (slack mismatch sig, github bad sig, stripe missing sig):
```
$ curl -sk -o /dev/null -w "%{http_code}\n" -X POST \
    -H 'X-Slack-Request-Timestamp: 0' -H 'X-Slack-Signature: v0=00' \
    --data '{}' http://localhost:8000/v1/integrations/slack/webhook
401
$ curl -sk -X POST -H 'X-Hub-Signature-256: sha256=00' \
    --data '{}' http://localhost:8000/v1/integrations/github/webhook
{"detail":"GitHub signature verification failed"}
$ curl -sk -X POST --data '{}' http://localhost:8000/webhooks/stripe
{"detail":"Imza header'i eksik"}   # i18n string (TR default at boot)
```

All three return generic strings; the taxonomy is in the audit log only.

---

## L24 counter

* Sweep 1 (R14): magic_token redact + Stripe checkout/billing str(exc)
  scrub (Q12-L24-001 HIGH + Q12-L24-002 MED)
* R18 follow-up: me_account.py PyJWT internals scrub
* R19 follow-up: me_data_export.py PyJWT internals scrub
* **Sweep 2 (R22): Slack response-body taxonomy leak (Q12-L24-003 MED)
  + 3-receiver audit silence (Q12-L24-004 LOW)**

L24 → **2/3** (sweep 2 ship; sweep 3 = remaining `str(exc)[:200]`
pattern across panel error handlers if any persist + Inngest webhook
SDK if it surfaces signing leaks at our boundary).
