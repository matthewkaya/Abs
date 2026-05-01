#!/usr/bin/env bash
# Sprint Hotfix CJ repro suite — 2026-04-29
# Boot the abs-cj stack first:
#   docker compose -p abs-cj -f infra/docker-compose.yml -f infra/docker-compose.dev.yml up -d --build backend
# Then:
#   bash artifacts/sprint_hotfix_cj/repro.sh
set -uo pipefail

BASE="${ABS_BASE_URL:-http://localhost:8000}"
COOKIE_BOOT=/tmp/abs_boot_cookies.txt
COOKIE_SETUP=/tmp/abs_setup_cookies.txt

pass=0
fail=0
expect() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS  $label  ($expected)"
        pass=$((pass + 1))
    else
        echo "  FAIL  $label  expected=$expected actual=$actual"
        fail=$((fail + 1))
    fi
}

echo "=== CJ-006 — RSA keypair + demo license bootstrap"
docker exec abs-cj-backend-1 sh -c 'ls /app/data/public.pem /app/data/private.pem /app/data/demo_license.jwt' >/dev/null 2>&1
expect "keypair files present" 0 $?

echo "=== CJ-007 — auth login (setup creds path)"
RES=$(curl -sk -X POST "$BASE/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@demo-acme.local","password":"LocalPass2026!"}' \
    -c "$COOKIE_SETUP" -o /dev/null -w "%{http_code}")
expect "setup-wizard creds → 200" 200 "$RES"
# Bootstrap fallback path is tested at end so it doesn't invalidate $COOKIE_SETUP.

echo "=== CJ-009 — quota_status"
RES=$(curl -sk -L "$BASE/v1/system/quota_status" -o /tmp/quota.json -w "%{http_code}")
expect "/v1/system/quota_status → 200" 200 "$RES"
HAS_FIELDS=$(python3 -c "import json; d=json.load(open('/tmp/quota.json')); print(int(all(k in d for k in ('claude_plus','free_providers','warnings'))))")
expect "schema complete (claude_plus+free_providers+warnings)" 1 "$HAS_FIELDS"

echo "=== CJ-001 — landing billing flag (frontend, manual check)"
echo "  INFO  npm run build  +  grep -c \"\\\$\" .next/static/chunks/page-*.js"

echo "=== CJ-003 — /auth/signup"
RES=$(curl -sk -X POST "$BASE/auth/signup" \
    -H "Content-Type: application/json" \
    -d '{"email":"hotfix@demo.co","tenant_slug":"hotfix-co"}' \
    -o /dev/null -w "%{http_code}")
expect "signup → 201" 201 "$RES"

echo "=== CJ-004 — anthropic skip free-tier"
# Not idempotent against in-flight setup; smoke variant only when state allows.
echo "  INFO  Run from a fresh setup_state: POST /v1/setup/step/anthropic {\"skip_paid_providers\":true}"

echo "=== CJ-005 — RFC 6761 .local email"
echo "  INFO  POST /v1/setup/step/admin {\"email\":\"admin@x.local\",\"password\":\"...\"} → 200"

echo "=== CJ-008 — marketplace"
COUNT=$(curl -sk -L "$BASE/v1/marketplace/plugins" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
expect "marketplace plugin count" 5 "$COUNT"
RES=$(curl -sk -L -b "$COOKIE_SETUP" -X POST "$BASE/v1/marketplace/install" \
    -H "Content-Type: application/json" \
    -d '{"plugin_id":"slack-receiver","tenant":"default"}' \
    -o /dev/null -w "%{http_code}")
[[ "$RES" == "201" || "$RES" == "200" ]]
expect "install slack-receiver → 200/201" 0 $?

echo "=== CJ-010 — 8 admin endpoints via panel session"
for ep in dashboard audit/recent errors/recent analytics/licenses analytics/churn me status/full vault/audit; do
    RES=$(curl -sk -L -b "$COOKIE_SETUP" -o /dev/null -w "%{http_code}" "$BASE/v1/admin/$ep")
    expect "/v1/admin/$ep" 200 "$RES"
done

echo "=== CJ-012 — /v1/update/changelog (200 not 503)"
RES=$(curl -sk -L -b "$COOKIE_SETUP" -o /dev/null -w "%{http_code}" "$BASE/v1/update/changelog")
expect "/v1/update/changelog → 200" 200 "$RES"

echo "=== CJ-007 — bootstrap fallback (destructive, last)"
# Snapshot admin_credentials.json then wipe; restore at end via setup wizard path.
docker exec abs-cj-backend-1 sh -c 'cp /app/data/admin_credentials.json /tmp/_creds_backup.json' >/dev/null 2>&1 || true
docker exec abs-cj-backend-1 rm -f /app/data/admin_credentials.json
RES=$(curl -sk -X POST "$BASE/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@local","password":"CHANGEME"}' \
    -c "$COOKIE_BOOT" -o /dev/null -w "%{http_code}")
expect "bootstrap admin@local → 200" 200 "$RES"
# Restore credentials for next runs.
docker exec abs-cj-backend-1 sh -c 'cp /tmp/_creds_backup.json /app/data/admin_credentials.json 2>/dev/null || true' >/dev/null 2>&1

echo
echo "─────────────────────────────────────────"
echo "PASS=$pass  FAIL=$fail"
exit "$fail"
