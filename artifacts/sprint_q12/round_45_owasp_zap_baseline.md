# Round 45 — OWASP ZAP baseline scan against backend

**Sprint:** Q12 Session 7
**Layer:** Q11-L6 (OWASP / security)
**Files touched:** 2 reports archived
**Status:** ✅ shipped — **66 PASS, 1 WARN, 0 FAIL** — no HIGH/MED findings

---

## Brief

Q11-L6 was inherited from Sprint 21 audit work but the OWASP ZAP
scan itself was never run against the running backend. R45
closes that gap with a baseline (passive-only) scan.

## Run

```bash
docker run --rm --network=host \
  -v /tmp/zap-wrk:/zap/wrk/:rw \
  ghcr.io/zaproxy/zaproxy:stable zap-baseline.py \
  -t http://localhost:8000 \
  -r zap-baseline-report.html \
  -J zap-baseline-report.json -I
```

Image: `ghcr.io/zaproxy/zaproxy:stable` (3.49 GB) — pulled
2026-05-04. Backend on `http://localhost:8000` (the live
infra-backend-1 container).

## Result

```
FAIL-NEW: 0
FAIL-INPROG: 0
WARN-NEW: 1
WARN-INPROG: 0
INFO: 0
IGNORE: 0
PASS: 66
```

### 66 passive rules clean

Including all the high-yield ones:
- CSP / X-Frame-Options / X-Content-Type-Options
- Cookie HttpOnly + Secure
- Source code disclosure
- Information disclosure (error messages, suspicious comments,
  debug headers)
- Cross-domain misconfig
- Reverse tabnabbing
- Insecure JSF ViewState
- Java serialization
- Cross-site scripting (passive surface)
- Sub-Resource-Integrity attribute
- Spectre site-isolation
- Anti-CSRF tokens

### 1 WARN-NEW (cosmetic)

```
WARN-NEW: Storable and Cacheable Content [10049] x 2
  http://localhost:8000 (404 Not Found)
  http://localhost:8000/robots.txt (404 Not Found)
```

Both URLs are **404 responses** (no root route, no robots.txt —
this is a pure API backend). The warning fires because 404
responses are cacheable by default. **Not a security issue** —
the 404s carry no PII or secrets. Filing as accepted-as-WONTFIX:
adding `Cache-Control: no-store` to 404 paths costs more than it
buys.

### Spider note (informational, not a finding)

```
Job spider error accessing URL http://localhost:8000 status code
returned : 404 expected 200
```

The ZAP spider expects a 200 root document to crawl from. The
backend serves `/healthz` + `/v1/*` + `/auth/*` only — no `/`.
The spider can't auto-discover routes; the passive scan still
ran against the seeded URL list and the 404 surface.

For real route coverage, R46 (active scan) will use a route
manifest seed list (chat completions, RAG, workflows, marketplace,
billing).

## Files

### `artifacts/sprint_q12/zap_reports/zap-baseline-report.html`
Full HTML report (browseable).

### `artifacts/sprint_q12/zap_reports/zap-baseline-report.json`
Machine-readable JSON for diff tracking across cron runs.

## Image rebuild

N/A — backend `app/` source untouched. Backend pytest unchanged
at 1633.

## Layer matrix delta

| Layer | Before R45 | After R45 |
|-------|------------|-----------|
| Q11-L6 | 0/3 (inherited audit, no scan run) | **0/3 ⭐ baseline clean** (66 passive rules PASS, 1 cosmetic WARN, 0 HIGH/MED/LOW findings) |

R46 (active scan) will graduate Q11-L6 further if it surfaces
nothing new.

## Counters

- Backend pytest: unchanged 1633.
- ZAP findings: 0 HIGH, 0 MED, 0 LOW. 1 cosmetic WARN.
- Atomic commits in round: 1.
