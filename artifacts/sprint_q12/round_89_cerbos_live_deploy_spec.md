# Round 89 — R76 Cerbos production live-deploy verify spec (founder gate)

**Date:** 2026-05-05
**Status:** SPEC — actual production deploy gated on founder approval.
**Branch HEAD:** post-R88.
**Source:** Q12-S9 R76 (HEAD 6debd63) shipped the cerbos.env map→list
fix (Caveat #12). Worker ran `helm template --dry-run` and committed
the Helm change; production cluster has NOT yet had the rollout.
This round documents the verification steps founder runs **after** the
real `helm upgrade`.

## Why "spec only"

S9 closing memo flagged the "shipped + test PASS ≠ live path works"
pattern. Cerbos was the textbook case — Helm coalesce silently dropped
the env block when shaped as a map, so policies were enforced in
chart-render but absent in the live deployment for an unknown window
before R76. R89 codifies the post-deploy verification ritual so the
next time we cannot accidentally ship "fix landed" without proof the
fix is alive in-cluster.

## Pre-deploy

```bash
# 1. Confirm we're on the post-R76 release.
git log --oneline -1 -- infra/helm/abs/templates/cerbos-deployment.yaml
# Expected to land on 6debd63 fix(q12/L27).

# 2. Render the chart and pin the env block format.
helm template abs infra/helm/abs/ -f infra/helm/abs/values.yaml | \
  yq '.spec.template.spec.containers[] | select(.name=="cerbos") | .env'
# Expected: a YAML LIST (each entry has `name:` and `value:`), not a
# map. R76 fix changed the source from `cerbos.env: { ... }` to a list
# under cerbos.envList[].
```

## Live deploy (founder, manual)

```bash
helm upgrade abs infra/helm/abs/ \
  --install \
  --namespace abs \
  --values infra/helm/abs/values.yaml \
  --atomic --timeout 5m
```

**Founder approval required before this command runs.**

## Post-deploy verify — 4 commands

```bash
# 1. helm get values must show env list, not map.
helm get values abs -n abs | yq '.cerbos.env // .cerbos.envList'
# Expected: list with at least 1 entry. If output is empty/null, the
# fix did NOT propagate; rollback.

# 2. kubectl describe must show the env vars on the running pod.
kubectl -n abs describe pod -l app.kubernetes.io/name=cerbos | \
  grep -A 5 "Environment:"
# Expected: every env name from values.yaml appears.

# 3. Live cerbos PDP returns the expected policy decisions.
POD=$(kubectl -n abs get pod -l app.kubernetes.io/name=cerbos -o jsonpath='{.items[0].metadata.name}')
kubectl -n abs exec "$POD" -- /cerbos/bin/cerbos compile /policies
# Expected: "0 errors". A non-zero exit means the policy bundle did
# not load — incident, page founder.

# 4. End-to-end sanity hit — known cross-tenant request must 403.
curl -sS -X POST https://abs.production.example/v1/marketplace/install \
  -H "Authorization: Bearer $CROSS_TENANT_TOKEN" \
  -d '{"plugin_id": "p_smoke", "tenant": "wrong-tenant"}'
# Expected: HTTP 403 cross_tenant_forbidden. If 200, the policy is not
# wired — incident.
```

## Round summary contract

When the founder runs the deploy, append to this file:

```yaml
deploy_id: <helm release revision>
deployed_at: <ISO 8601 UTC>
deployed_by: founder@…
helm_get_values_match: true|false   # output of step 1
kubectl_describe_env_present: true|false   # step 2
cerbos_compile_clean: true|false   # step 3
cross_tenant_403: true|false   # step 4
live_path_verified: true|false   # AND of steps 1-4
```

Only a `live_path_verified: true` row closes Caveat #12 in production.

## Skip rationale (worker)

This round is intentionally a SPEC and not an executed task. The
worker has no production cluster credentials and the brief's
section 7 forbids touching the production cluster. Founder picks up
from "Live deploy" above.
