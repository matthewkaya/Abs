#!/usr/bin/env bash
# Q7 Phase B — Marketplace hardening repro (cosign skip + sandbox + idempotency).
# Assumes ABS backend running at http://localhost:8000 with demo admin seeded.
set -uo pipefail
cd "$(dirname "$0")/../../.."
COOKIE=/tmp/q7b_cookie.txt
pass=0; fail=0
expect() {
    if [[ "$2" == "$3" ]]; then
        echo "  PASS  $1 ($2)"
        pass=$((pass+1))
    else
        echo "  FAIL  $1 expected=$2 actual=$3"
        fail=$((fail+1))
    fi
}

echo "=== Q7 Phase B — Marketplace hardening ==="

# Defense-in-depth: re-seed admin so this repro works after a chain run
# wiped the auth state. Idempotent.
if [[ -x scripts/dev/credential_reset.sh ]]; then
    bash scripts/dev/credential_reset.sh demo >/dev/null 2>&1 || true
fi

# Also clear any pre-existing tenant install state to keep the install
# count assertion stable across re-runs.
docker exec abs-cj-backend-1 rm -f /app/data/marketplace_installs.json >/dev/null 2>&1 || true

# Login
curl -sk -X POST http://localhost:8000/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"admin@demo-acme.local","password":"LocalPass2026!"}' \
    -c "$COOKIE" -o /dev/null

# Install 5 plugins
for p in slack-receiver gmail-archiver linear-bridge notion-sync postgres-mirror; do
    RC=$(curl -sk -b "$COOKIE" -X POST http://localhost:8000/v1/marketplace/install \
        -H "Content-Type: application/json" \
        -d "{\"plugin_id\":\"$p\"}" -o /dev/null -w "%{http_code}")
    if [[ "$RC" == "201" || "$RC" == "200" ]]; then
        expect "install $p" 1 1
    else
        expect "install $p" 1 0
    fi
done

# List
COUNT=$(curl -sk -b "$COOKIE" http://localhost:8000/v1/marketplace/installed | \
    python3 -c "import json,sys; print(len(json.load(sys.stdin)['installed']))")
expect "installed count == 5" 5 "$COUNT"

# Idempotent
RC=$(curl -sk -b "$COOKIE" -X POST http://localhost:8000/v1/marketplace/install \
    -H "Content-Type: application/json" \
    -d '{"plugin_id":"slack-receiver"}' -o /tmp/q7b_idem.json -w "%{http_code}")
expect "idempotent install" 200 "$RC"
STATUS=$(python3 -c "import json; print(json.load(open('/tmp/q7b_idem.json'))['status'])")
expect "idempotent status" "already_installed" "$STATUS"

# Uninstall
RC=$(curl -sk -b "$COOKIE" -X DELETE \
    http://localhost:8000/v1/marketplace/uninstall/slack-receiver \
    -o /dev/null -w "%{http_code}")
expect "uninstall slack-receiver" 200 "$RC"

# Uninstall non-existent
RC=$(curl -sk -b "$COOKIE" -X DELETE \
    http://localhost:8000/v1/marketplace/uninstall/slack-receiver \
    -o /dev/null -w "%{http_code}")
expect "uninstall 404" 404 "$RC"

echo
echo "─────────────────────────────────────────"
echo "PASS=$pass  FAIL=$fail"
exit "$fail"
