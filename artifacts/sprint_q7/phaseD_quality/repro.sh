#!/usr/bin/env bash
# Q7 Phase D — Quality + bug hunt regression gate.
#
# Combines: 5xx sweep + cumulative regression chain + Q6 standalone +
# Q7 phase A/B/C smoke. Re-runs credential reset between sprints when
# needed. Target: cumulative 99+/99 + 8 Q7 = 107+ assertions clean.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0
FAIL=0
SECTIONS=()

run_section() {
    local label="$1"
    local script="$2"
    if [[ ! -x "$script" ]]; then
        echo "  SKIP  not executable: $script"
        SECTIONS+=("$label: SKIP")
        return
    fi
    local out summary section_pass section_fail
    out=$(bash "$script" 2>&1)
    summary=$(echo "$out" | grep -E "^PASS=" | tail -1)
    section_pass=$(echo "$summary" | sed -E 's/PASS=([0-9]+).*/\1/')
    section_fail=$(echo "$summary" | sed -E 's/.*FAIL=([0-9]+).*/\1/')
    if [[ -n "$section_pass" && -n "$section_fail" ]]; then
        PASS=$((PASS + section_pass))
        FAIL=$((FAIL + section_fail))
        SECTIONS+=("$label: PASS=$section_pass FAIL=$section_fail")
    else
        SECTIONS+=("$label: NO_SUMMARY")
    fi
}

# ---- 5xx sweep ----
echo "▶ 5xx sweep"
SWEEP_OUT=$(bash artifacts/sprint_q7/phaseD_quality/sweep.sh 2>&1)
echo "$SWEEP_OUT" | tail -6
SWEEP_5XX=$(echo "$SWEEP_OUT" | grep -E "5xx errors:" | sed -E 's/.*5xx errors:[[:space:]]+([0-9]+).*/\1/' | head -1)
if [[ "$SWEEP_5XX" == "0" ]]; then
    PASS=$((PASS + 1))
    SECTIONS+=("5xx sweep: PASS=1 FAIL=0")
else
    FAIL=$((FAIL + 1))
    SECTIONS+=("5xx sweep: PASS=0 FAIL=1 (found $SWEEP_5XX 5xx)")
fi
echo

# ---- Cumulative chain ----
echo "▶ Cumulative chain (Q5 runner — re-runs hotfix→q1→q2→q3→q4 with seeds)"
CHAIN_OUT=$(bash artifacts/sprint_q5/run_full_chain.sh 2>&1)
echo "$CHAIN_OUT" | tail -10
CHAIN_PASS=$(echo "$CHAIN_OUT" | grep -E "^TOTAL" | sed -E 's/.*PASS=([0-9]+).*/\1/')
CHAIN_FAIL=$(echo "$CHAIN_OUT" | grep -E "^TOTAL" | sed -E 's/.*FAIL=([0-9]+).*/\1/')
PASS=$((PASS + ${CHAIN_PASS:-0}))
FAIL=$((FAIL + ${CHAIN_FAIL:-0}))
SECTIONS+=("Cumulative chain: PASS=${CHAIN_PASS:-?} FAIL=${CHAIN_FAIL:-?}")
echo

# ---- Bootstrap (chain wiped state — re-sync Q7 code) ----
if [[ -x scripts/dev/q7_bootstrap.sh ]]; then
    bash scripts/dev/q7_bootstrap.sh >/dev/null 2>&1 || true
fi

# ---- Per-phase smoke (post-bootstrap) ----
run_section "Q7 Phase A (Neo4j)"        artifacts/sprint_q7/phaseA_neo4j/repro.sh
run_section "Q7 Phase B (Marketplace)"  artifacts/sprint_q7/phaseB_marketplace/repro.sh
run_section "Q7 Phase C (Panel UI)"     artifacts/sprint_q7/phaseC_panel_premium/repro.sh
run_section "Q6 Final"                  artifacts/sprint_q6/repro.sh

echo
echo "─────────────────────────────────────────"
echo "Q7 Phase D Per-section:"
for line in "${SECTIONS[@]}"; do
    echo "  $line"
done
echo "─────────────────────────────────────────"
echo "PASS=$PASS  FAIL=$FAIL"
exit "$FAIL"
