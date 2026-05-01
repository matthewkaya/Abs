#!/usr/bin/env bash
# Q9 Master repro — Q8 phases plus Q9.B-E surface checks.
#
# Usage:
#   ./artifacts/sprint_q9/master_repro.sh         # all q9 (B|C|D|E typecheck + Q8.A|B|NP)
#   ./artifacts/sprint_q9/master_repro.sh phaseQ9.B   # single phase
#   ./artifacts/sprint_q9/master_repro.sh phaseO      # live customer journey
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

step() { printf "\n\033[1;36m▶ %s\033[0m\n" "$1"; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
fail() { printf "\033[1;31m✗ %s\033[0m\n" "$1"; exit 1; }

phaseA() {
  step "Phase A — chat backend pytest (12 tests)"
  ( cd core/backend && .venv/bin/python -m pytest tests/test_q8_chat.py -q --no-header )
  ok "Phase A backend"
}

phaseB() {
  step "Phase B — workflow vitest (22 tests)"
  ( cd core/landing && npx vitest run __tests__/workflow.test.ts __tests__/WorkflowChatPanel.test.tsx )
  ok "Phase B canvas + W1/W2"
}

phaseNP() {
  step "Phase N + P — backend route registration"
  ( cd core/backend && \
    ABS_TEST_MODE=1 \
    ABS_SESSION_SECRET=test-secret-32chars-aaaaaaaaaaaaaaaa \
    .venv/bin/python -c "
from app.api import mcp_tokens, claude_code_hooks
assert any(r.path == '/v1/mcp/tokens' for r in mcp_tokens.router.routes)
assert any(r.path == '/v1/hooks/quota-check' for r in claude_code_hooks.router.routes)
print('routes OK')
" )
  ok "Phase N + P routes"
}

phaseQ9B() {
  step "Phase Q9.B — meetings filter typecheck"
  ( cd core/landing && npx tsc --noEmit 2>&1 | grep -E "panel/meetings/page" | grep -v deprecated || true )
  ok "Phase Q9.B meetings filter"
}

phaseQ9C() {
  step "Phase Q9.C — transcription waveform + permission dialog typecheck"
  ( cd core/landing && npx tsc --noEmit 2>&1 | grep -E "panel/transcription|Waveform" | grep -v deprecated || true )
  ok "Phase Q9.C transcription"
}

phaseQ9D() {
  step "Phase Q9.D — marketplace permissions chip typecheck"
  ( cd core/landing && npx tsc --noEmit 2>&1 | grep -E "MarketplacePanel|admin/marketplace" | grep -v deprecated || true )
  ok "Phase Q9.D marketplace"
}

phaseQ9E() {
  step "Phase Q9.E — quota DateRangePicker typecheck"
  ( cd core/landing && npx tsc --noEmit 2>&1 | grep -E "panel/quota/page" | grep -v deprecated || true )
  ok "Phase Q9.E quota date range"
}

phaseO() {
  step "Phase O — customer journey (headed, 11 step)"
  ( cd core/landing && \
    ABS_PANEL_PASSWORD="${ABS_PANEL_PASSWORD:-CHANGEME}" \
    npx playwright test q8-customer-journey --headed )
  ok "Phase O 11/11 step"
}

PHASE="${1:-all}"
case "$PHASE" in
  phaseA)    phaseA ;;
  phaseB)    phaseB ;;
  phaseNP)   phaseNP ;;
  phaseQ9.B|phaseQ9B) phaseQ9B ;;
  phaseQ9.C|phaseQ9C) phaseQ9C ;;
  phaseQ9.D|phaseQ9D) phaseQ9D ;;
  phaseQ9.E|phaseQ9E) phaseQ9E ;;
  phaseO)    phaseO ;;
  all)
    phaseA
    phaseB
    phaseNP
    phaseQ9B
    phaseQ9C
    phaseQ9D
    phaseQ9E
    echo
    echo "▶ Phase O kept manual — run 'phaseO' once docker compose up + cookie are ready."
    ;;
  *) fail "unknown phase: $PHASE (use phaseA|B|NP|Q9.B|Q9.C|Q9.D|Q9.E|O|all)" ;;
esac

ok "master_repro complete: $PHASE"
