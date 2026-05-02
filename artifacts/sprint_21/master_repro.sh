#!/usr/bin/env bash
# Sprint 21 — Perf Architecture reproduction script.
#
# Usage:
#   bash artifacts/sprint_21/master_repro.sh bundle      # ANALYZE build + diff
#   bash artifacts/sprint_21/master_repro.sh lighthouse  # 4-page throttled run
#   bash artifacts/sprint_21/master_repro.sh regression  # Q8+Q10+Q11 specs
#   bash artifacts/sprint_21/master_repro.sh all
#
# Pre-req: /tmp/q10-standalone bundle running on :3458, backend on :8000.

set -euo pipefail

phase="${1:-bundle}"

bundle() {
  cd core/landing
  rm -rf .next
  ANALYZE=true npm run build 2>&1 | grep -E '/panel|/admin'
  cp .next/analyze/client.html ../../artifacts/sprint_21/bundle_analyzer_client_post.html
  cat .next/app-build-manifest.json | python3 -c "
import json, sys, os
m = json.load(sys.stdin)
pages = m.get('pages', {})
for k in ['/panel/page', '/panel/chat/page', '/panel/tools/page', '/panel/quota/page', '/admin/workflow-builder/page']:
    chunks = pages.get(k, [])
    total = sum(os.path.getsize('.next/' + c) for c in chunks if c.startswith('static/chunks') and os.path.exists('.next/' + c))
    print(f'{k:35} {total // 1024}K total ({len(chunks)} chunks)')
"
}

lighthouse() {
  cd core/landing
  COOKIE=$(curl -sk -X POST http://localhost:3458/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@demo-acme.com","password":"DemoPass2026!"}' -i \
    | grep -i 'set-cookie' | sed 's/.*abs_session=//; s/;.*//')
  mkdir -p ../../artifacts/sprint_21/lighthouse
  for SLUG in panel chat tools quota; do
    if [ "$SLUG" = "panel" ]; then URL="http://localhost:3458/panel"
    else URL="http://localhost:3458/panel/$SLUG"; fi
    npx --yes lighthouse@12 "$URL" \
      --preset=desktop \
      --throttling-method=devtools \
      --throttling.cpuSlowdownMultiplier=4 \
      --throttling.requestLatencyMs=400 \
      --throttling.downloadThroughputKbps=400 \
      --throttling.uploadThroughputKbps=200 \
      --output=json --output-path=../../artifacts/sprint_21/lighthouse/lh_${SLUG}_throttled.json \
      --extra-headers="{\"Cookie\":\"abs_session=${COOKIE}\"}" \
      --chrome-flags="--headless" --quiet 2>&1 | tail -1
  done
  node -e "
['panel','chat','tools','quota'].forEach(s => {
  const r = require('../../artifacts/sprint_21/lighthouse/lh_' + s + '_throttled.json');
  const c = r.categories;
  const a = r.audits;
  console.log(s.padEnd(8),
    'perf:', Math.round(c.performance.score*100),
    'LCP:', Math.round(a['largest-contentful-paint'].numericValue) + 'ms',
    'CLS:', a['cumulative-layout-shift'].numericValue.toFixed(3),
    'TBT:', Math.round(a['total-blocking-time'].numericValue) + 'ms',
    'FCP:', Math.round(a['first-contentful-paint'].numericValue) + 'ms');
});"
}

regression() {
  (cd core/backend && source .venv/bin/activate && python -m pytest tests/test_q8_chat.py tests/test_q10_l1_coverage.py tests/test_q10_l2_integration.py tests/test_q11_l10_stress.py tests/test_q11_l10_stress_deep.py tests/test_q11_l10_cascade_race.py tests/test_q11_l13_fuzz.py tests/test_q11_l14_data_integrity.py tests/test_q11_l14_alembic_roundtrip.py tests/test_q11_l15_openapi_contract.py tests/test_q11_l15_drift.py -q)
  cd core/landing
  PLAYWRIGHT_BASE_URL=http://localhost:3458 \
    ABS_PANEL_EMAIL=admin@demo-acme.com \
    ABS_PANEL_PASSWORD=DemoPass2026! \
    npx playwright test \
      q10-no-api-degradation q10-l3-theme-matrix q10-l7-visual \
      q11-l11 q11-l12 \
      --project=chromium-desktop --reporter=line
}

case "$phase" in
  bundle)     bundle ;;
  lighthouse) lighthouse ;;
  regression) regression ;;
  all)        bundle && lighthouse && regression ;;
  *)          echo "Usage: $0 {bundle|lighthouse|regression|all}"; exit 1 ;;
esac
