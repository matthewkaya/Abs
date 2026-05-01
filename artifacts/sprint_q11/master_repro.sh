#!/usr/bin/env bash
# Sprint Q11 — full reproduction script.
#
# Usage:
#   bash artifacts/sprint_q11/master_repro.sh smoke      # quick backend
#   bash artifacts/sprint_q11/master_repro.sh backend    # all backend tests
#   bash artifacts/sprint_q11/master_repro.sh frontend   # all e2e (needs prod build)
#   bash artifacts/sprint_q11/master_repro.sh all        # everything
#
# Assumes:
#   * working directory = repo root
#   * core/backend/.venv set up (python -m venv .venv && pip install -e .)
#   * core/landing/node_modules set up (npm ci --legacy-peer-deps)
#   * playwright browsers installed (npx playwright install chromium firefox webkit)
#   * /tmp/q10-standalone bundle prepared via:
#       cd core/landing && npm run build
#       cp -r .next/standalone /tmp/q10-standalone
#       cp -r .next/static /tmp/q10-standalone/.next/
#       cp -r public /tmp/q10-standalone/
#       HOSTNAME=localhost PORT=3458 ABS_BACKEND_URL=http://localhost:8000 \
#         node /tmp/q10-standalone/server.js &

set -euo pipefail

phase="${1:-smoke}"

backend_smoke() {
  cd core/backend
  source .venv/bin/activate
  python -m pytest \
    tests/test_q8_chat.py \
    tests/test_q10_l1_coverage.py \
    tests/test_q10_l2_integration.py \
    tests/test_q11_l10_stress.py \
    tests/test_q11_l13_fuzz.py \
    -q
}

backend_full() {
  cd core/backend
  source .venv/bin/activate
  python -m pytest \
    tests/test_q8_chat.py \
    tests/test_q10_l1_coverage.py \
    tests/test_q10_l2_integration.py \
    tests/test_q11_l10_stress.py \
    tests/test_q11_l10_stress_deep.py \
    tests/test_q11_l10_cascade_race.py \
    tests/test_q11_l13_fuzz.py \
    tests/test_q11_l14_data_integrity.py \
    tests/test_q11_l14_alembic_roundtrip.py \
    tests/test_q11_l15_openapi_contract.py \
    tests/test_q11_l15_drift.py \
    -q
}

frontend_full() {
  cd core/landing
  export PLAYWRIGHT_BASE_URL=http://localhost:3458
  export ABS_PANEL_EMAIL=admin@demo-acme.com
  export ABS_PANEL_PASSWORD=DemoPass2026!
  npx vitest run __tests__/Demo.test.tsx __tests__/Q11ErrorUx.test.ts
  npx playwright test \
    q10-no-api-degradation \
    q10-l3-theme-matrix \
    q10-l7-visual \
    q10-a11y-axe \
    q11-l11-cross-browser \
    q11-l12-responsive \
    --project=chromium-desktop \
    --reporter=line
  npx playwright test \
    q10-l3-theme-matrix \
    q10-a11y-axe \
    q11-l11-cross-browser \
    --project=firefox-desktop --project=webkit-desktop \
    --reporter=line
}

case "$phase" in
  smoke)    backend_smoke ;;
  backend)  backend_full ;;
  frontend) frontend_full ;;
  all)      backend_full && (cd ../.. && frontend_full) ;;
  *)        echo "Usage: $0 {smoke|backend|frontend|all}"; exit 1 ;;
esac
