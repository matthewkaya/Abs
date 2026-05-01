#!/usr/bin/env bash
# Sprint 19 + Q2 master repro — re-runs the 4 shipped phases.
# Pre-req: docker compose abs-cj stack healthy + Next.js dev (optional).
set -uo pipefail

cd "$(dirname "$0")/../.."
COOKIE=/tmp/q2_master_cookie.txt
pass=0
fail=0
expect() {
    if [[ "$2" == "$3" ]]; then
        echo "  PASS  $1  ($2)"
        pass=$((pass + 1))
    else
        echo "  FAIL  $1  expected=$2 actual=$3"
        fail=$((fail + 1))
    fi
}

# Login (Q1 admin)
expect "auth login" 200 "$(curl -sk -X POST http://localhost:8000/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"qa@abs.local","password":"QaSprint2026!"}' \
    -c "$COOKIE" -o /dev/null -w '%{http_code}')"

# ---- Phase 1: workflows ----
echo "=== Phase 1 — workflow synthesize / execute ==="
RES=$(curl -sk -L -b "$COOKIE" -X POST http://localhost:8000/v1/workflows/synthesize \
    -H "Content-Type: application/json" \
    -d '{"intent":"Slack #support kanalına yeni mesaj → Linear issue","locale":"tr"}' \
    -o /tmp/wf.json -w "%{http_code}")
expect "/v1/workflows/synthesize" 200 "$RES"
NODES=$(python3 -c "import json; print(len(json.load(open('/tmp/wf.json'))['workflow']['nodes']))" 2>/dev/null || echo 0)
[[ "$NODES" -ge 3 ]] && expect "synth nodes >= 3" 1 1 || expect "synth nodes >= 3" 1 0
WF=$(python3 -c "import json; d=json.load(open('/tmp/wf.json')); print(json.dumps(d['workflow']))")
RES=$(curl -sk -L -b "$COOKIE" -X POST http://localhost:8000/v1/workflows/execute \
    -H "Content-Type: application/json" \
    -d "{\"workflow\":$WF,\"dry_run\":true}" \
    -o /dev/null -w "%{http_code}")
expect "/v1/workflows/execute (dry_run)" 200 "$RES"

# ---- Phase 4: UsageLog seed → 80% warning ----
echo "=== Phase 4 — UsageLog A7 trigger ==="
docker exec abs-cj-backend-1 python3 -c "
from app.services.usage_log import reset_for_tests, append
reset_for_tests()
for _ in range(850):
    append('anthropic', tokens=1000)
" >/dev/null 2>&1
WARN=$(curl -sk -L -b "$COOKIE" http://localhost:8000/v1/system/quota_status \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['warnings'])" 2>/dev/null)
[[ "$WARN" == *"claude_plus_warning_80"* ]] && expect "quota warning_80" 1 1 || expect "quota warning_80" 1 0

# ---- Phase 5: tenant JWT mint ----
echo "=== Phase 5 — tenant JWT mint + Cerbos gate ==="
TOKEN=$(docker exec abs-cj-backend-1 python3 -c "
import sys; sys.path.insert(0, '/app')
from tests.util.mint_tenant_jwt import mint
print(mint('tenant-acme', subject='qa@abs.local'))
" 2>/dev/null)
[[ "${#TOKEN}" -gt 200 ]] && expect "JWT minted" 1 1 || expect "JWT minted" 1 0
RAG_CODE=$(curl -sk -X POST http://localhost:8000/v1/rag/query \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query":"x","top_k":1}' -o /dev/null -w "%{http_code}")
# Expect 403 (auth passed, policy DENY for unseeded tenant) — NOT 401
[[ "$RAG_CODE" == "403" ]] && expect "RAG gate Cerbos DENY (auth passed)" 1 1 || expect "RAG gate Cerbos DENY (auth passed)" 1 0

# ---- Phase 6: golden Q-A dataset ----
echo "=== Phase 6 — golden_qa_50.json ==="
COUNT=$(python3 -c "import json; print(len(json.load(open('core/backend/tests/fixtures/golden_qa_50.json'))))")
expect "Q-A count" 50 "$COUNT"

echo
echo "─────────────────────────────────────────"
echo "PASS=$pass  FAIL=$fail"
exit "$fail"
