#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
CK=artifacts/sprint_q1_quality/personas/A2/cookies.txt
OUT=artifacts/sprint_q1_quality/effectiveness/C3
mkdir -p "$OUT"
ENDPOINTS=(
  "/healthz"
  "/v1/system/quota_status"
  "/v1/system/feature_usage"
  "/v1/meetings"
  "/v1/marketplace/plugins"
  "/v1/admin/dashboard"
  "/v1/admin/me"
  "/v1/license/status"
  "/v1/update/changelog"
  "/v1/tts/voices"
  "/v1/panel/cascade/recent"
  "/v1/panel/tools"
)

for ep in "${ENDPOINTS[@]}"; do
  out=$(echo "$ep" | tr / _).times
  for i in $(seq 1 100); do
    /usr/bin/curl -sk -L -b "$CK" --max-time 5 -o /dev/null \
      -w "%{time_total}\n" "http://localhost:8000$ep"
  done | sort -n > "$OUT/$out"
done
python3 - <<'PY'
import os, glob
out_dir = "artifacts/sprint_q1_quality/effectiveness/C3"
print(f'{"endpoint":<35} samples  p50_ms   p95_ms   p99_ms')
table = []
for f in sorted(glob.glob(f"{out_dir}/*.times")):
    times = sorted(float(l)*1000 for l in open(f) if l.strip())
    if not times: continue
    n = len(times)
    p50 = times[int(n*0.50)-1]
    p95 = times[int(n*0.95)-1]
    p99 = times[int(n*0.99)-1]
    name = os.path.basename(f).replace(".times", "").replace("_", "/").lstrip("/")
    table.append((name, n, p50, p95, p99))
    print(f"/{name:<34} {n:>7} {p50:7.1f} {p95:8.1f} {p99:8.1f}")
breaches = [t for t in table if t[3] > 200.0]
print(f"\np95 breaches (>200ms): {len(breaches)}")
for b in breaches:
    print(f"  /{b[0]} p95={b[3]:.1f}ms")
PY
