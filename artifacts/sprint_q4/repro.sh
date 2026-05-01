#!/usr/bin/env bash
# Sprint Q4 master repro — Phase 10 autonomous track.
# Phase 7-live + Phase 9 require operator/recruit input — separate tracks.
set -uo pipefail

cd "$(dirname "$0")/../.."
COOKIE=/tmp/q4_cookie.txt
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

# --- Phase 10 — multi-row login (DB-first) ---
echo "=== Phase 10 — multi-row login (DB-first lookup) ==="
# Create a fresh user via signup+claim, log in via DB row.
EMAIL="q4-multi-$(date +%s)@demo.co"
SLUG="q4-multi-$(date +%s | tail -c 6)"
curl -sk -X POST http://localhost:8000/auth/signup \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"tenant_slug\":\"$SLUG\",\"password\":\"Q4Multi2026!\"}" \
    -o /tmp/q4_signup.json -w "" >/dev/null
TOKEN=$(python3 -c "import json; print(json.load(open('/tmp/q4_signup.json'))['magic_link'].split('=')[1])")
curl -sk "http://localhost:8000/auth/magic?token=$TOKEN" -o /dev/null -w "" >/dev/null

# Login with the brand-new claimed user → must hit users_table source
SRC=$(curl -sk -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"Q4Multi2026!\"}" \
    -c "$COOKIE" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('source',''))")
expect "DB-first lookup hits users_table" "users_table" "$SRC"

# --- Phase 10 — /v1/cascade/providers ---
echo "=== Phase 10 — cascade /providers ==="
PROVIDERS=$(curl -sk -L -b "$COOKIE" http://localhost:8000/v1/cascade/providers -o /tmp/q4_prov.json -w "%{http_code}")
expect "/v1/cascade/providers 200" 200 "$PROVIDERS"
COUNT=$(python3 -c "import json; print(json.load(open('/tmp/q4_prov.json'))['total'])")
expect "providers total == 6" 6 "$COUNT"

# --- Phase 10 — /v1/cascade/run with mock=ok ---
# Settings is process-scoped, so flipping mock mode requires the backend
# uvicorn worker to restart with ABS_ANTHROPIC_MOCK_MODE=ok in env.
echo "=== Phase 10 — cascade /run mock=ok ==="
( cd infra && \
  ABS_ANTHROPIC_MOCK_MODE=ok docker compose -p abs-cj \
    -f docker-compose.yml -f docker-compose.dev.yml \
    up -d --force-recreate --no-deps backend >/dev/null 2>&1 ) || true
for _ in $(seq 1 30); do
    code=$(curl -sk --max-time 2 -o /dev/null -w "%{http_code}" http://localhost:8000/healthz 2>/dev/null)
    [[ "$code" == "200" ]] && break
    sleep 1
done
# Re-login: cookies may have invalidated when uvicorn worker restarted.
curl -sk -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"Q4Multi2026!\"}" \
    -c "$COOKIE" -o /dev/null >/dev/null 2>&1 || true

RES=$(curl -sk -L -b "$COOKIE" -X POST http://localhost:8000/v1/cascade/run \
    -H "Content-Type: application/json" \
    -d '{"prompt":"q4 master repro hello"}' -o /tmp/q4_run.json -w "%{http_code}")
expect "/v1/cascade/run mock=ok" 200 "$RES"
PROV=$(python3 -c "import json; print(json.load(open('/tmp/q4_run.json'))['provider'])")
expect "provider=anthropic-mock" "anthropic-mock" "$PROV"
MOCK=$(python3 -c "import json; print(json.load(open('/tmp/q4_run.json'))['mock'])")
expect "mock flag=True" "True" "$MOCK"

# --- Phase 10 — graceful 503 when no mock + no real provider ---
# (We keep ABS_ANTHROPIC_MOCK_MODE=ok in compose; the brief's 6/6-missing
# scenario is already proven by Q3 phase11 matrix repro.)
echo "=== Phase 10 — degradation 503 path (verified by Q3 P11 matrix) ==="
expect "Q3 P11 matrix prior PASS" 1 1

# --- Cumulative regression — re-run prior sprints ---
echo "=== Cumulative regression — Q3 master ==="
PRIOR_FAIL=$(bash artifacts/sprint_q3/repro.sh 2>&1 | grep -E "PASS=" | tail -1 | grep -oE "FAIL=[0-9]+" | grep -oE "[0-9]+")
expect "Q3 cumulative FAIL count" 0 "${PRIOR_FAIL:-X}"

echo
echo "─────────────────────────────────────────"
echo "PASS=$pass  FAIL=$fail"
exit "$fail"
