#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
CK=artifacts/sprint_q1_quality/personas/A2/cookies.txt
OUT=artifacts/sprint_q1_quality/effectiveness/C4
mkdir -p "$OUT"
ENDPOINTS=(
  "/healthz" "/v1/system/quota_status" "/v1/meetings"
  "/v1/marketplace/plugins" "/v1/admin/dashboard"
  "/v1/license/status" "/v1/tts/voices" "/v1/admin/me"
)
TOTAL=0
FAIL=0
> "$OUT/flake.txt"
for ep in "${ENDPOINTS[@]}"; do
  ok=0
  bad=0
  for i in $(seq 1 1000); do
    code=$(/usr/bin/curl -sk -L -b "$CK" --max-time 5 -o /dev/null \
        -w "%{http_code}" "http://localhost:8000$ep")
    if [[ "$code" == "200" ]]; then
      ok=$((ok + 1))
    else
      bad=$((bad + 1))
    fi
  done
  rate=$(python3 -c "print(f'{$bad/10:.4f}')")
  echo "${ep} ok=$ok bad=$bad rate=${rate}%" | tee -a "$OUT/flake.txt"
  TOTAL=$((TOTAL + ok + bad))
  FAIL=$((FAIL + bad))
done
overall=$(python3 -c "print(f'{$FAIL*100/$TOTAL:.4f}')")
echo "OVERALL flake_rate=${overall}% total=${TOTAL} fail=${FAIL}" | tee -a "$OUT/flake.txt"
