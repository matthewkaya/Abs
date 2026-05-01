#!/usr/bin/env bash
# Sprint 20 implementation repro suite — 2026-04-29
# Pre-req: docker compose up backend + piper + whisperx, npm run dev (landing)
set -uo pipefail

BACKEND="${ABS_BACKEND_URL:-http://localhost:8000}"
LANDING="${ABS_LANDING_URL:-http://localhost:3000}"
COOKIE=/tmp/s20_cookie.txt

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

echo "=== Login (post-hotfix admin) ==="
RES=$(curl -sk -X POST "$BACKEND/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@demo-acme.local","password":"LocalPass2026!"}' \
    -c "$COOKIE" -o /dev/null -w "%{http_code}")
expect "auth login" 200 "$RES"

echo "=== Sprint 20 GET endpoints ==="
for path in "/v1/system/quota_status" "/v1/system/feature_usage" "/v1/meetings" "/v1/tts/voices"; do
    RES=$(curl -sk -L -b "$COOKIE" --max-time 10 -o /dev/null -w "%{http_code}" "$BACKEND$path")
    expect "GET $path" 200 "$RES"
done

echo "=== Sprint 20 POST hot-paths ==="

echo "  S20.1 — Piper TTS synthesize"
RES=$(curl -sk -L -b "$COOKIE" -X POST "$BACKEND/v1/tts/synthesize" \
    -H "Content-Type: application/json" \
    -d '{"text":"Merhaba dunya","voice":"tr_TR-fettah-medium"}' \
    -o /tmp/s20_tts.wav -w "%{http_code}")
expect "POST /v1/tts/synthesize" 200 "$RES"
RIFF=$(head -c 4 /tmp/s20_tts.wav 2>/dev/null)
expect "TTS output is WAV (RIFF magic)" "RIFF" "$RIFF"

echo "  S20.2 — WhisperX transcribe (synthetic fixture)"
FIXTURE="core/backend/tests/fixtures/meeting_demo.wav"
if [[ -f "$FIXTURE" ]]; then
    RES=$(curl -sk -L -b "$COOKIE" -X POST "$BACKEND/v1/transcribe" \
        -F "audio=@$FIXTURE" \
        -o /tmp/s20_tx.json -w "%{http_code}")
    expect "POST /v1/transcribe" 200 "$RES"
    SCHEMA_OK=$(python3 -c "
import json
d = json.load(open('/tmp/s20_tx.json'))
print(int(all(k in d for k in ('duration_sec','speakers','segments','summary'))))" 2>/dev/null)
    expect "transcribe schema (duration_sec/speakers/segments/summary)" 1 "$SCHEMA_OK"
else
    echo "  SKIP   fixture not found at $FIXTURE"
fi

echo "  S20.4 — /v1/meetings/upload + persistence"
if [[ -f "$FIXTURE" ]]; then
    RES=$(curl -sk -L -b "$COOKIE" -X POST "$BACKEND/v1/meetings/upload" \
        -F "audio=@$FIXTURE" \
        -o /tmp/s20_meet.json -w "%{http_code}")
    expect "POST /v1/meetings/upload" 201 "$RES"
fi
RES=$(curl -sk -L -b "$COOKIE" "$BACKEND/v1/meetings" \
    -o /tmp/s20_meet_list.json -w "%{http_code}")
expect "GET /v1/meetings (list after upload)" 200 "$RES"

echo "  S20.3 — feature_usage assertion"
COUNT=$(curl -sk -L -b "$COOKIE" "$BACKEND/v1/system/feature_usage" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['feature_count'])" 2>/dev/null)
expect "feature_count == 29" 29 "$COUNT"

echo "=== Sprint 20 frontend panels (Next.js dev) ==="
for path in "/panel/meetings" "/panel/transcription" "/panel/quota"; do
    RES=$(curl -sk -L --max-time 60 -o /dev/null -w "%{http_code}" "$LANDING$path")
    expect "GET $path" 200 "$RES"
done

echo
echo "─────────────────────────────────────────────"
echo "PASS=$pass  FAIL=$fail"
exit "$fail"
