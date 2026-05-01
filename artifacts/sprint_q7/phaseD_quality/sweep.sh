#!/usr/bin/env bash
# Q7 Phase D — 5xx sweep across all GET routes from openapi.json.
#
# Hits every documented GET route as the seeded admin and records HTTP
# status. Any 5xx is a regression; 200/2xx/3xx/401/403/404/422 are noise
# (auth/payload-shape — not server faults).
#
# Usage:
#   bash artifacts/sprint_q7/phaseD_quality/sweep.sh
# Output:
#   /tmp/q7d_sweep.log — full status × route inventory
#   stdout — summary + any 5xx lines

set -uo pipefail
cd "$(dirname "$0")/../../.."

COOKIE=/tmp/q7d_cookie.txt
LOG=/tmp/q7d_sweep.log
> "$LOG"

# Pre-flight: re-seed admin (Q7 Phase D defense-in-depth).
bash scripts/dev/credential_reset.sh demo >/dev/null 2>&1 || true
curl -sk -X POST http://localhost:8000/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"admin@demo-acme.local","password":"LocalPass2026!"}' \
    -c "$COOKIE" -o /dev/null

# Pull routes from OpenAPI spec.
ROUTES_RAW=$(curl -sk http://localhost:8000/openapi.json)
if [[ -z "$ROUTES_RAW" ]]; then
    echo "✗ openapi.json unreachable — backend down?" >&2
    exit 2
fi

# Emit "<METHOD> <PATH>" pairs (only GET — POST/DELETE need bodies).
echo "$ROUTES_RAW" | python3 -c "
import json, sys
spec = json.load(sys.stdin)
for path, methods in spec.get('paths', {}).items():
    for method in methods.keys():
        if method.upper() == 'GET':
            print(f'GET {path}')
" > /tmp/q7d_routes.txt

TOTAL=0
FIVEXX=0
NON_2XX_NON_AUTH=0

while IFS= read -r line; do
    METHOD="${line%% *}"
    PATH_PART="${line#* }"

    # Replace path params with safe stub values.
    PATH_RESOLVED=$(echo "$PATH_PART" | sed -E 's/\{[^/]+\}/test/g')

    STATUS=$(curl -sk -b "$COOKIE" \
        -o /dev/null -w "%{http_code}" \
        --max-time 8 \
        "http://localhost:8000${PATH_RESOLVED}" 2>/dev/null || echo "000")

    echo "$STATUS $METHOD $PATH_RESOLVED" >> "$LOG"
    TOTAL=$((TOTAL + 1))
    if [[ "$STATUS" =~ ^5 ]]; then
        FIVEXX=$((FIVEXX + 1))
    fi
    if [[ ! "$STATUS" =~ ^[23] ]] && [[ "$STATUS" != "401" && "$STATUS" != "403" && "$STATUS" != "404" && "$STATUS" != "422" ]]; then
        NON_2XX_NON_AUTH=$((NON_2XX_NON_AUTH + 1))
    fi
done < /tmp/q7d_routes.txt

echo "─────────────────────────────────────────"
echo "Q7 Phase D Sweep Summary"
echo "  Total GET routes hit: $TOTAL"
echo "  5xx errors:           $FIVEXX"
echo "  Other non-2xx (excl. 401/403/404/422): $NON_2XX_NON_AUTH"
echo

if [[ "$FIVEXX" -gt 0 ]]; then
    echo "▶ 5xx routes:"
    grep -E "^5" "$LOG"
    echo
    exit "$FIVEXX"
fi

echo "✓ no 5xx — sweep clean"
exit 0
