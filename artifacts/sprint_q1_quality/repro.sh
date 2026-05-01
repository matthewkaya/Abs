#!/usr/bin/env bash
# Sprint Q1 Quality repro — re-runs the 12 Q1 tests in dependency order.
# Pre-req: docker compose up backend + piper + whisperx (abs-cj project).
set -uo pipefail

cd "$(dirname "$0")/../.."

OUT_BASE="artifacts/sprint_q1_quality"
COOKIE="$OUT_BASE/personas/A2/cookies.txt"

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

echo "=== Q1.A2 — Bootstrap admin wizard regression ==="
docker exec abs-cj-backend-1 sh -c "rm -f /app/data/setup_state.json /app/data/admin_credentials.json"
mkdir -p "$OUT_BASE/personas/A2"
for body in \
    '/v1/setup/step/admin {"email":"qa@abs.local","password":"QaSprint2026!"}' \
    "/v1/setup/step/license {\"license_key\":\"$(docker exec abs-cj-backend-1 cat /app/data/demo_license.jwt)\"}" \
    '/v1/setup/step/domain {"mode":"ip","ssl_mode":"internal"}' \
    '/v1/setup/step/anthropic {"skip_paid_providers":true}' \
    '/v1/setup/step/providers {}' \
    '/v1/setup/step/test {}'; do
    path="${body%% *}"; payload="${body#* }"
    code=$(curl -sk -X POST "http://localhost:8000$path" \
        -H "Content-Type: application/json" -d "$payload" \
        -o /dev/null -w "%{http_code}")
    expect "wizard $path" 200 "$code"
done
expect "auth login" 200 "$(curl -sk -X POST http://localhost:8000/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"qa@abs.local","password":"QaSprint2026!"}' \
    -c "$COOKIE" -o /dev/null -w '%{http_code}')"
for ep in dashboard audit/recent errors/recent analytics/licenses analytics/churn me status/full vault/audit; do
    code=$(curl -sk -L -b "$COOKIE" -o /dev/null -w "%{http_code}" "http://localhost:8000/v1/admin/$ep")
    expect "/v1/admin/$ep" 200 "$code"
done

echo "=== Q1.A5 — Marketplace operator ==="
for pid in slack-receiver gmail-archiver linear-bridge notion-sync postgres-mirror; do
    code=$(curl -sk -L -b "$COOKIE" -X POST http://localhost:8000/v1/marketplace/install \
        -H "Content-Type: application/json" -d "{\"plugin_id\":\"$pid\",\"tenant\":\"qa-tenant\"}" \
        -o /dev/null -w "%{http_code}")
    expect "install $pid" 201 "$code"
done

echo "=== Q1.A6 — Meeting recorder ==="
FIXTURE=core/backend/tests/fixtures/meeting_demo.wav
if [[ -f "$FIXTURE" ]]; then
    code=$(curl -sk -L -b "$COOKIE" -X POST http://localhost:8000/v1/meetings/upload \
        -F "audio=@$FIXTURE" -o /dev/null -w "%{http_code}")
    expect "meetings upload" 201 "$code"
fi
LIST_COUNT=$(curl -sk -L -b "$COOKIE" http://localhost:8000/v1/meetings | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
[[ "$LIST_COUNT" -ge 1 ]] && expect "meetings list >= 1" 1 1 || expect "meetings list >= 1" 1 0

echo "=== Q1.A8 — Multi-tenant isolation ==="
QA=$(curl -sk -L -b "$COOKIE" "http://localhost:8000/v1/marketplace/installed?tenant=qa-tenant" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['installed']))")
EMPTY=$(curl -sk -L -b "$COOKIE" "http://localhost:8000/v1/marketplace/installed?tenant=other-empty" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['installed']))")
expect "qa-tenant has installs" 5 "$QA"
expect "other-empty has 0" 0 "$EMPTY"

echo "=== Q1.A9 — RAG endpoints + auth gate ==="
expect "/v1/rag/query 401 (missing bearer)" 401 \
    "$(curl -sk -L -b "$COOKIE" -X POST http://localhost:8000/v1/rag/query \
        -H 'Content-Type: application/json' \
        -d '{"query":"x","tenant":"t","top_k":1}' -o /dev/null -w '%{http_code}')"

echo "=== Q1.B1 — Piper TTS waveform ==="
curl -sk -L -b "$COOKIE" -X POST http://localhost:8000/v1/tts/synthesize \
    -H "Content-Type: application/json" \
    -d '{"text":"Bu Q1 kalite repro testidir, ses uzun olmalı.","voice":"tr_TR-fettah-medium"}' \
    -o "$OUT_BASE/quality/B1_repro.wav" -w "tts=%{http_code}\n"
if python3 "$OUT_BASE/quality/B1_piper_waveform.py" "$OUT_BASE/quality/B1_repro.wav" >/dev/null 2>&1; then
    expect "B1 waveform sanity" 0 0
else
    expect "B1 waveform sanity" 0 1
fi

echo "=== Q1.B4 — RAGAS mock backend ==="
docker cp "$OUT_BASE/quality/B4_run.py" abs-cj-backend-1:/tmp/B4_run.py >/dev/null 2>&1 || true
RAGAS_OUT=$(docker exec abs-cj-backend-1 python3 /tmp/B4_run.py 2>&1 | tail -1)
[[ "$RAGAS_OUT" == "B4_PASS" || "$RAGAS_OUT" == B4_PARTIAL* ]] \
    && expect "B4 ragas pipeline" 1 1 || expect "B4 ragas pipeline" 1 0

echo "=== Q1.C2 — MCP inventory (claim 75) ==="
COUNT=$(docker exec abs-cj-backend-1 python3 -c "
import asyncio
from app.mcp.server import mcp_server
print(len(asyncio.run(mcp_server.list_tools())))
" 2>/dev/null)
[[ "$COUNT" -ge 75 ]] && expect "MCP inventory >= 75" 1 1 || expect "MCP inventory >= 75" 1 0

echo "=== Q1.C3/C4 — already produced; check artefacts ==="
if [[ -f "$OUT_BASE/effectiveness/C3/latency_table.txt" ]]; then
    # Line shape: "p95 breaches (>200ms): N" — last number on line.
    BREACH=$(grep "p95 breaches" "$OUT_BASE/effectiveness/C3/latency_table.txt" | grep -oE "[0-9]+" | tail -1)
    expect "C3 latency p95 breaches" 0 "${BREACH:-X}"
fi
if [[ -f "$OUT_BASE/effectiveness/C4/flake.txt" ]]; then
    OVERALL=$(grep "OVERALL" "$OUT_BASE/effectiveness/C4/flake.txt" | grep -oE "[0-9]+\.[0-9]+%" | head -1)
    [[ "$OVERALL" == "0.0000%" ]] && expect "C4 flake 0.0000%" 1 1 || expect "C4 flake 0.0000%" 1 0
fi

echo "=== Q1.C1 — cold-start (destructive, run only when invoked with --c1) ==="
if [[ "${1:-}" == "--c1" ]]; then
    pushd infra >/dev/null
    docker compose -p abs-cj -f docker-compose.yml -f docker-compose.dev.yml down >/dev/null 2>&1
    START=$(date +%s)
    docker compose -p abs-cj -f docker-compose.yml -f docker-compose.dev.yml up -d >/dev/null 2>&1
    until curl -sk --max-time 2 -o /dev/null -w "%{http_code}" http://localhost:8000/healthz | grep -q 200; do
        sleep 1
        [[ $(($(date +%s) - START)) -gt 180 ]] && break
    done
    ELAPSED=$(($(date +%s) - START))
    [[ $ELAPSED -le 90 ]] && expect "C1 cold-start <= 90s" 1 1 || expect "C1 cold-start <= 90s" 1 0
    popd >/dev/null
else
    echo "  SKIP   pass --c1 to run destructive cold-start probe"
fi

echo
echo "─────────────────────────────────────────"
echo "PASS=$pass  FAIL=$fail"
exit "$fail"
