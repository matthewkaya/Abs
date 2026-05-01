# Required Field vs Customer Promise Report — Sprint Hotfix CJ

**Run date:** 2026-04-29
**Trigger bug:** BUG-CJ-004 (Anthropic key required conflicts with Claude Plus promise)
**Status:** ✅ PASS

## Promise reference

`docs/ABS_HYBRID_TIER_PROMISE.md` (shipped Sprint 20 T-F04):
- Free tier: Claude Plus chat subscription + 5 free-API providers
  (Groq, Gemini, Cerebras, Cohere, Cloudflare). **No Anthropic API key.**
- Paid tier: customer-supplied Anthropic API key for higher-throughput jobs.

## Setup form (Step 4 — Anthropic) before/after

| Aspect | Before | After |
|--------|--------|-------|
| Anthropic key field | `required minlength=8 pattern=sk-ant-...` | optional, validated only if not skipped |
| Skip checkbox | none | `<input type="checkbox" id="setup-skip-paid">` |
| Hidden flag | none | `skip_paid_providers` synced from checkbox |
| Backend body | `AnthropicBody.anthropic_api_key: str` (required) | `Optional[str]` + `skip_paid_providers: bool` + `model_validator` |

## Behavioural matrix

| Input | HTTP | `paid_skipped` | Anthropic stored? |
|-------|------|----------------|-------------------|
| `{anthropic_api_key:"sk-ant-abc1234"}` | 200 | false | yes (encrypted vault) |
| `{anthropic_api_key:"sk-ant-abc1234", skip_paid_providers:false}` | 200 | false | yes |
| `{skip_paid_providers:true}` | 200 | true | no |
| `{skip_paid_providers:true, anthropic_api_key:"sk-ant-abc1234"}` | 200 | true | no (validator clears) |
| `{anthropic_api_key:""}` | 422 | n/a | n/a |
| `{}` | 422 | n/a | n/a (paid tier requires key) |

## Setup wizard journey (free-tier walkthrough)

1. Step 1 admin → 200 (CJ-005 covers `.local` TLDs)
2. Step 2 license → 200 with `demo_license.jwt` (CJ-006 keypair bootstrap)
3. Step 3 domain → 200
4. Step 4 anthropic with `skip_paid_providers=true` → 200, `paid_skipped=true`
5. Step 5 providers → 200 (any subset, all optional)
6. Step 6 test → 200, `setup_state.completed=true`

End-to-end the wizard now reflects the customer promise — paid SaaS opt-in only.

## Carry-over

- Multi-tier conditional UI (paid vs free) is a single checkbox today; for future
  pricing iterations the wizard might show a "tier" picker upstream of Step 4.
