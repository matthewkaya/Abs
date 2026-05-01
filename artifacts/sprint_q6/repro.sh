#!/usr/bin/env bash
# Sprint Q6 master repro — Phase A pricing strip + Phase B auth gate.
# Phase C scripts ship but require Playwright + sharp; not run here.
set -uo pipefail

cd "$(dirname "$0")/../.."
COOKIE=/tmp/q6_cookie.txt
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

# Pre-flight: seed admin so login works in chained run
docker exec abs-cj-backend-1 python3 -m tests.util.state_reset clean >/dev/null 2>&1 || true
docker exec abs-cj-backend-1 python3 -c "
import bcrypt, json, time
from pathlib import Path
hash_b = bcrypt.hashpw('LocalPass2026!'.encode(), bcrypt.gensalt()).decode()
Path('/app/data/admin_credentials.json').write_text(json.dumps({'email':'admin@demo-acme.local','password_hash':hash_b,'created_at':time.time(),'tenant_slug':'default'},ensure_ascii=False))
Path('/app/data/setup_state.json').write_text(json.dumps({'completed':True,'current_step':6,'completed_steps':['admin','license','domain','anthropic','providers','test'],'started_at':0,'completed_at':0,'lang':'en','data':{}}))
" >/dev/null 2>&1

echo "=== Phase A — pricing strip ==="
# Customer-facing pricing strings should be 0
HITS=$(grep -rEn "\\\$299|€299|\\\$1000|\\\$1,000|tek seferlik|14 gün koşulsuz iade|14-day no-questions|Self-Host \\\$" \
    core/landing/app core/landing/components core/landing/locales 2>/dev/null \
    | grep -v node_modules | grep -v "\.next" | grep -v test | grep -v __tests__ \
    | grep -v "^.*:[0-9]\+://" \
    | wc -l | tr -d ' ')
# Allow 1 hit for the deprecation comment in PricingPage.tsx
[[ "$HITS" -le 1 ]] && expect "customer-facing pricing strings <= 1 (deprecation comment OK)" 1 1 \
    || expect "customer-facing pricing strings <= 1" 1 0

# Live: showcase no longer shows $1,142
SHOW_HIT=$(/usr/bin/curl -sk --max-time 10 http://localhost:3000/showcase 2>/dev/null | grep -oE '\$1,142|\+\$310' | wc -l | tr -d ' ')
expect "showcase strips \$1,142 / +\$310" 0 "$SHOW_HIT"

# /pricing redirect
PR_RES=$(/usr/bin/curl -sk -o /dev/null -w "%{http_code}" "http://localhost:3000/pricing")
expect "/pricing redirects" 307 "$PR_RES"

echo "=== Phase B — auth gate ==="
# 1. /auth/login proxy
RES=$(/usr/bin/curl -sk -X POST http://localhost:3000/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@demo-acme.local","password":"LocalPass2026!"}' \
    -c "$COOKIE" -o /tmp/q6_login.json -w "%{http_code}")
expect "/auth/login proxy POST" 200 "$RES"

# 2. cookie set
COOKIE_LINE=$(grep "abs_session" "$COOKIE" 2>/dev/null | head -1)
[[ -n "$COOKIE_LINE" ]] && expect "abs_session cookie set" 1 1 || expect "abs_session cookie set" 1 0

# 3. /v1/* proxy with cookie
for ep in /v1/admin/me /v1/cascade/providers /v1/system/quota_status /v1/marketplace/plugins; do
    code=$(/usr/bin/curl -sk -L -b "$COOKIE" -o /dev/null -w "%{http_code}" "http://localhost:3000$ep")
    expect "proxy $ep" 200 "$code"
done

# 4. middleware redirect when no cookie
REDIRECT=$(/usr/bin/curl -sk -o /dev/null -w "%{http_code}|%{redirect_url}" "http://localhost:3000/panel/meetings")
[[ "$REDIRECT" == "307|http://localhost:3000/login?next=%2Fpanel%2Fmeetings" ]]
expect "/panel/meetings unauth → /login redirect" 0 $?

# 5. /login frontend page
LOGIN_CODE=$(/usr/bin/curl -sk -o /dev/null -w "%{http_code}" "http://localhost:3000/login")
expect "/login page" 200 "$LOGIN_CODE"

echo "=== Phase C — tour scripts shipped ==="
[[ -f core/landing/cj_annotated_tour.mjs ]] && expect "cj_annotated_tour.mjs shipped" 1 1 \
    || expect "cj_annotated_tour.mjs shipped" 1 0
[[ -f core/landing/cj_hero_collage.mjs ]] && expect "cj_hero_collage.mjs shipped" 1 1 \
    || expect "cj_hero_collage.mjs shipped" 1 0

echo
echo "─────────────────────────────────────────"
echo "PASS=$pass  FAIL=$fail"
exit "$fail"
