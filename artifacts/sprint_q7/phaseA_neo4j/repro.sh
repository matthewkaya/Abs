#!/usr/bin/env bash
# Q7 Phase A — Neo4j integration smoke
set -uo pipefail
cd "$(dirname "$0")/../../.."
COOKIE=/tmp/q7a_cookie.txt
pass=0; fail=0
expect() { if [[ "$2" == "$3" ]]; then echo "  PASS  $1 ($2)"; pass=$((pass+1)); else echo "  FAIL  $1 expected=$2 actual=$3"; fail=$((fail+1)); fi; }

echo "=== Q7 Phase A — Neo4j ==="

# Defense-in-depth: re-seed admin so this repro works after a chain run
# wiped the auth state. Idempotent; no-op when credential is already current.
if [[ -x scripts/dev/credential_reset.sh ]]; then
    bash scripts/dev/credential_reset.sh demo >/dev/null 2>&1 || true
fi

# Pre-flight (operator): bring neo4j up under the abs-cj project so it
# joins the same docker network as the backend container:
#   docker compose -p abs-cj -f infra/docker-compose.yml \
#     -f infra/docker-compose.dev.yml up -d neo4j
# Without -p abs-cj the container lands on infra_default and the backend
# can't DNS-resolve `neo4j:7687`. If the wrong-network case happens:
#   docker network connect --alias neo4j abs-cj_default abs-cj-neo4j
# Backend container also needs the neo4j Python driver:
#   docker exec abs-cj-backend-1 pip install "neo4j>=5.18"
# (or rebuild image with updated requirements.txt / pyproject.toml).

# Pre-flight: neo4j up?
NEO4J_HEALTH=$(docker exec abs-cj-neo4j cypher-shell -u neo4j -p AbsNeo2026! "RETURN 1 AS ok" 2>/dev/null | grep -c "1" || echo 0)
expect "neo4j container responsive" 1 "$NEO4J_HEALTH"

# Login (admin@demo-acme.local / LocalPass2026!)
curl -sk -X POST http://localhost:8000/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"admin@demo-acme.local","password":"LocalPass2026!"}' \
    -c "$COOKIE" -o /dev/null

# Health
HC=$(curl -sk -b "$COOKIE" http://localhost:8000/v1/graph/health -o /tmp/q7a_health.json -w "%{http_code}")
expect "/v1/graph/health 200" 200 "$HC"

# Ingest
RC=$(curl -sk -b "$COOKIE" -X POST http://localhost:8000/v1/graph/ingest \
    -H "Content-Type: application/json" \
    -d @core/backend/tests/fixtures/graph_seed.json \
    -o /tmp/q7a_ingest.json -w "%{http_code}")
expect "/v1/graph/ingest 200" 200 "$RC"

# Cypher count
RC=$(curl -sk -b "$COOKIE" -X POST http://localhost:8000/v1/graph/cypher \
    -H "Content-Type: application/json" \
    -d '{"cypher":"MATCH (p:Person)-[:WORKS_AT]->(c:Company {name: \"DemoCo\"}) RETURN count(p) AS n","params":{}}' \
    -o /tmp/q7a_cypher.json -w "%{http_code}")
expect "/v1/graph/cypher 200" 200 "$RC"
COUNT=$(python3 -c "import json; d=json.load(open('/tmp/q7a_cypher.json')); print(d['data'][0]['n'])" 2>/dev/null || echo 0)
expect "DemoCo employees == 2" 2 "$COUNT"

# Destructive guard
RC=$(curl -sk -b "$COOKIE" -X POST http://localhost:8000/v1/graph/cypher \
    -H "Content-Type: application/json" \
    -d '{"cypher":"MATCH (n) DETACH DELETE n","params":{}}' \
    -o /dev/null -w "%{http_code}")
expect "destructive guard 400" 400 "$RC"

echo
echo "─────────────────────────────────────────"
echo "PASS=$pass  FAIL=$fail"
exit "$fail"
