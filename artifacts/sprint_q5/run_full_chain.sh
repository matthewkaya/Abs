#!/usr/bin/env bash
# Q5.CO1 — Master chain runner with state isolation between sprints.
#
# Each sprint's repro.sh assumes a fresh data layer; chaining them after
# Q3/Q4 magic-link mutations would otherwise leak state. We snapshot the
# current state once, clean the DB + state files between sprints, then
# restore at the end so the developer's working environment is preserved.
set -uo pipefail

cd "$(dirname "$0")/../.."

OUT="artifacts/sprint_q5/phaseQ5CO1_state_iso/chain_report.log"
mkdir -p "$(dirname "$OUT")"
> "$OUT"

# Stash baseline so the operator's logged-in user doesn't get clobbered.
docker exec abs-cj-backend-1 python3 -m tests.util.state_reset snapshot --sprint=baseline >/dev/null 2>&1 || true

# Pre-flight: ensure helper modules are present in the container (older
# images may not have them baked in yet — re-copy is idempotent).
docker exec abs-cj-backend-1 mkdir -p /app/tests/util >/dev/null 2>&1 || true
for f in __init__.py mint_tenant_jwt.py state_reset.py; do
    docker cp "core/backend/tests/util/$f" "abs-cj-backend-1:/app/tests/util/$f" >/dev/null 2>&1 || true
done

# Pre-flight: Next.js dev must be on :3000 for S20 frontend probes. If
# nothing's listening, S20's panel routes will return code 000 and the
# chain reports them as FAIL.
NEXT_OK=$(/usr/bin/curl -sk --max-time 3 -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null)
if [[ "$NEXT_OK" != "200" ]]; then
    echo "  WARN  Next.js dev not on :3000 (status=$NEXT_OK) — S20 panel routes will FAIL" | tee -a "$OUT"
fi

SPRINTS=(
    "sprint_hotfix_cj"
    "sprint_20_impl"
    "sprint_q1_quality"
    "sprint_q2_master"
    "sprint_q3"
    "sprint_q4"
)

PASS=0
FAIL=0
PER_SPRINT=()

seed_admin() {
    local email="$1"
    local password="$2"
    docker exec abs-cj-backend-1 python3 -c "
import bcrypt, json, time
from pathlib import Path
data = Path('/app/data')
data.mkdir(parents=True, exist_ok=True)
hash_b = bcrypt.hashpw('$password'.encode(), bcrypt.gensalt()).decode()
(data / 'admin_credentials.json').write_text(json.dumps({
    'email': '$email', 'password_hash': hash_b, 'created_at': time.time(),
    'tenant_slug': 'default', 'source': 'chain_seed'
}, ensure_ascii=False))
(data / 'setup_state.json').write_text(json.dumps({
    'completed': True, 'current_step': 6,
    'completed_steps': ['admin','license','domain','anthropic','providers','test'],
    'started_at': 0, 'completed_at': 0, 'lang': 'en', 'data': {}
}))
" >/dev/null 2>&1
}

for sprint in "${SPRINTS[@]}"; do
    echo "════════════════════════════════════════════" | tee -a "$OUT"
    echo "▶ $sprint" | tee -a "$OUT"
    echo "════════════════════════════════════════════" | tee -a "$OUT"

    docker exec abs-cj-backend-1 python3 -m tests.util.state_reset clean >/dev/null 2>&1 || true

    # Per-sprint baseline seed — each sprint expects a specific admin
    # email already present in admin_credentials.json + setup_state in
    # "completed" mode so FirstRunMiddleware doesn't 307 the requests.
    case "$sprint" in
        sprint_hotfix_cj|sprint_20_impl)
            seed_admin "admin@demo-acme.local" "LocalPass2026!"
            ;;
        sprint_q1_quality)
            # Q1.A2 wipes + runs its own setup wizard — leave clean.
            ;;
        sprint_q2_master)
            seed_admin "qa@abs.local" "QaSprint2026!"
            ;;
        sprint_q3|sprint_q4)
            # Signup-based; only needs setup_state completed.
            seed_admin "admin@demo-acme.local" "LocalPass2026!"
            ;;
    esac

    if [[ ! -x "artifacts/$sprint/repro.sh" ]]; then
        echo "  SKIP no repro.sh" | tee -a "$OUT"
        continue
    fi

    bash "artifacts/$sprint/repro.sh" 2>&1 | tee -a "$OUT" >/dev/null
    SUMMARY=$(grep -E "^PASS=" "$OUT" | tail -1)
    PER_SPRINT+=("$sprint: $SUMMARY")
    SPRINT_PASS=$(echo "$SUMMARY" | sed -E 's/PASS=([0-9]+).*/\1/')
    SPRINT_FAIL=$(echo "$SUMMARY" | sed -E 's/.*FAIL=([0-9]+).*/\1/')
    PASS=$((PASS + SPRINT_PASS))
    FAIL=$((FAIL + SPRINT_FAIL))
    echo "  $SUMMARY" | tee -a "$OUT"
done

# Restore the baseline so the operator's session keeps working.
docker exec abs-cj-backend-1 python3 -m tests.util.state_reset restore --sprint=baseline >/dev/null 2>&1 || true

echo | tee -a "$OUT"
echo "─────────────────────────────────────────" | tee -a "$OUT"
echo "Per-sprint:" | tee -a "$OUT"
for line in "${PER_SPRINT[@]}"; do
    echo "  $line" | tee -a "$OUT"
done
echo "─────────────────────────────────────────" | tee -a "$OUT"
echo "TOTAL  PASS=$PASS  FAIL=$FAIL" | tee -a "$OUT"
exit "$FAIL"
