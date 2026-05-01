#!/usr/bin/env bash
# Q7 Master Repro — Phase A + B + C smoke + cumulative chain regression.
#
# Runs: credential reset → Phase A neo4j → Phase B marketplace → Phase C panel
#       → Q5 cumulative chain → Q6 standalone → final tally.
#
# Target: 107/107 (99 cumulative + 8 Q7 phase smoke).

set -uo pipefail
cd "$(dirname "$0")/../.."

CREDENTIAL_RESET="scripts/credential_reset.sh"
Q7_BOOTSTRAP="scripts/q7_bootstrap.sh"
PASS=0
FAIL=0
SECTIONS=()

run_section() {
    local label="$1"
    local script="$2"
    echo "════════════════════════════════════════════"
    echo "▶ $label"
    echo "════════════════════════════════════════════"
    if [[ ! -x "$script" ]]; then
        echo "  SKIP  not executable: $script"
        SECTIONS+=("$label: SKIP (not executable)")
        return
    fi
    local before_pass=$PASS
    local before_fail=$FAIL
    local out
    out=$(bash "$script" 2>&1)
    echo "$out"
    local section_pass section_fail summary
    summary=$(echo "$out" | grep -E "^PASS=" | tail -1)
    section_pass=$(echo "$summary" | sed -E 's/PASS=([0-9]+).*/\1/')
    section_fail=$(echo "$summary" | sed -E 's/.*FAIL=([0-9]+).*/\1/')
    if [[ -n "$section_pass" && -n "$section_fail" ]]; then
        PASS=$((PASS + section_pass))
        FAIL=$((FAIL + section_fail))
        SECTIONS+=("$label: PASS=$section_pass FAIL=$section_fail")
    else
        SECTIONS+=("$label: NO SUMMARY (script exit=$?)")
    fi
}

# Pre-flight: bootstrap Q7 code into backend container (dev-only; production
# rebuilds the image), then re-seed credentials (defense-in-depth Phase D).
echo "─── pre-flight: Q7 bootstrap ───"
if [[ -x "$Q7_BOOTSTRAP" ]]; then
    bash "$Q7_BOOTSTRAP" 2>&1 | tail -10
fi
echo "─── pre-flight: credential reset ───"
if [[ -x "$CREDENTIAL_RESET" ]]; then
    bash "$CREDENTIAL_RESET" 2>&1 | tail -3
fi

# Q7 finalize — outside-the-container live curl probes (catches the exact
# production gap that left graph router 404 on the rebuilt image).
echo
echo "═══ Q7.A LIVE — /v1/graph/* dış curl ═══"
LIVE_PASS=0
LIVE_FAIL=0
COOKIE=/tmp/q7_master_live.txt
LOGIN_CODE=$(curl -sk -c "$COOKIE" -X POST http://localhost:8000/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@demo-acme.local","password":"LocalPass2026!"}' \
    -o /dev/null -w "%{http_code}")
if [[ "$LOGIN_CODE" == "200" ]]; then
    echo "  PASS  auth login (200)"
    LIVE_PASS=$((LIVE_PASS + 1))
else
    echo "  FAIL  auth login ($LOGIN_CODE)"
    LIVE_FAIL=$((LIVE_FAIL + 1))
fi
for ep in cypher ingest nl-query; do
    case "$ep" in
        cypher)   PAYLOAD='{"cypher":"RETURN 1 AS ok"}' ;;
        ingest)   PAYLOAD='{"entities":[{"label":"Person","props":{"id":"q7live","name":"x"}}]}' ;;
        nl-query) PAYLOAD='{"intent":"x","locale":"tr"}' ;;
    esac
    CODE=$(curl -sk -b "$COOKIE" -X POST "http://localhost:8000/v1/graph/$ep" \
        -d "$PAYLOAD" -H "Content-Type: application/json" \
        -o /dev/null -w "%{http_code}" --max-time 8)
    if [[ "$CODE" =~ ^(200|400|422)$ ]]; then
        echo "  PASS  /v1/graph/$ep ($CODE)"
        LIVE_PASS=$((LIVE_PASS + 1))
    else
        echo "  FAIL  /v1/graph/$ep = $CODE (404 olmamalı)"
        LIVE_FAIL=$((LIVE_FAIL + 1))
    fi
done
PASS=$((PASS + LIVE_PASS))
FAIL=$((FAIL + LIVE_FAIL))
SECTIONS+=("Q7.A live curl: PASS=$LIVE_PASS FAIL=$LIVE_FAIL")
echo

# Phase A — Neo4j
run_section "Q7 Phase A (Neo4j)"        "artifacts/sprint_q7/phaseA_neo4j/repro.sh"

# Phase B — Marketplace
run_section "Q7 Phase B (Marketplace)"  "artifacts/sprint_q7/phaseB_marketplace/repro.sh"

# Phase C — Panel premium (static checks only; full Lighthouse runs separately)
run_section "Q7 Phase C (Panel UI)"     "artifacts/sprint_q7/phaseC_panel_premium/repro.sh"

# Phase D — quality (regression + sweep)
run_section "Q7 Phase D (Quality)"      "artifacts/sprint_q7/phaseD_quality/repro.sh"

# Cumulative regression — Q5 chain (re-runs hotfix→q1→q2→q3→q4 with seeds)
run_section "Cumulative chain (Q5 runner)"  "artifacts/sprint_q5/run_full_chain.sh"

# Q6 standalone
run_section "Q6 Final"                  "artifacts/sprint_q6/repro.sh"

echo
echo "─────────────────────────────────────────"
echo "Per-section:"
for line in "${SECTIONS[@]}"; do
    echo "  $line"
done
echo "─────────────────────────────────────────"
echo "TOTAL  PASS=$PASS  FAIL=$FAIL"

# Target: 99 cumulative + 8 Q7 = 107 PASS.
if [[ "$PASS" -ge 107 && "$FAIL" -eq 0 ]]; then
    echo "✅ Q7 MASTER PASS — cumulative target met"
    exit 0
fi
echo "❌ Q7 MASTER FAIL — investigate per-section above"
exit "$FAIL"
