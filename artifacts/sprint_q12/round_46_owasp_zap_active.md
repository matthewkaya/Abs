# Round 46 — OWASP ZAP **active** scan against backend

**Sprint:** Q12 Session 7
**Layer:** Q11-L6 (OWASP / security) — graduation
**Files touched:** 2 reports archived
**Status:** ✅ shipped — **141 PASS, 1 WARN, 0 FAIL/HIGH/MED**

---

## Run

```bash
docker run --rm --network=host \
  -v /tmp/zap-wrk:/zap/wrk/:rw \
  ghcr.io/zaproxy/zaproxy:stable zap-full-scan.py \
  -t http://localhost:8000 \
  -r zap-active-report.html \
  -J zap-active-report.json \
  -m 5 -I
```

Image: `ghcr.io/zaproxy/zaproxy:stable`. Backend on `localhost:8000`
(infra-backend-1). `-m 5` caps spider at 5 minutes; the active-rule
sweep runs until completion regardless.

## Result

```
FAIL-NEW: 0
FAIL-INPROG: 0
WARN-NEW: 1
WARN-INPROG: 0
PASS: 141
```

### 141 active rules clean

Headline categories all PASS:

- **Injection family**: Path Traversal, Remote File Inclusion,
  Server Side Code Injection, Remote OS Command Injection
  (sync + time-based), XPath Injection, XSLT Injection, SOAP
  XML Injection, Server Side Template Injection (sync + blind),
  Expression Language Injection, NoSQL Injection (MongoDB sync
  + time-based), XML External Entity Attack
- **High-profile CVEs**: Log4Shell [40043], Spring4Shell [40045],
  Text4shell [40047], React2Shell [40048]
- **Server-side**: SSRF [40046], Padding Oracle, Cloud Metadata
  Exposure, Spring Actuator Information Leak
- **Source disclosure**: Git, SVN, .htaccess, .env, ELMAH,
  Trace.axd, Hidden File Finder
- **DoS**: Exponential Entity Expansion (Billion Laughs Attack)
  [40044]
- **Bypass**: 403 Bypassing
- **Cookie**: HttpOnly + Secure verified, Slack-loose detector
- **CORS**: clean
- **HTTP method**: Insecure HTTP Method (TRACE/DELETE/etc) clean

### 1 WARN-NEW (dev-only, expected)

```
WARN-NEW: HTTP Only Site [10106] x 1
  http://localhost:8000/ (0)
```

The backend serves over HTTP on localhost:8000 — in production
it sits behind Caddy with HTTPS termination. This warning fires
because ZAP saw raw HTTP without HSTS.

**Filed as accepted-as-WONTFIX** for the dev environment. The
Caddy production config in `infra/Caddyfile` already enforces
HTTPS + HSTS headers; this WARN does not represent a real
production risk.

## Files

### `artifacts/sprint_q12/zap_reports/zap-active-report.html`
Full HTML report — browseable per-rule findings.

### `artifacts/sprint_q12/zap_reports/zap-active-report.json`
Machine-readable JSON for diff tracking across cron runs.

## Image rebuild

N/A — backend `app/` source untouched. The active scan exercises
the *running* backend, not the source tree. Backend pytest
unchanged at 1636 (R51 +3 just before).

## Layer matrix delta

| Layer | Before R46 | After R46 |
|-------|------------|-----------|
| Q11-L6 | 0/3 ⭐ baseline (R45 66 PASS) | **0/3 ⭐⭐ baseline + active** (R45 66 + R46 141 = 207 unique rules clean; 0 HIGH/MED/LOW; 2 cosmetic WARNs both dev-only) |

## Counters

- Backend pytest: 1636 PASS / 14 skipped (no change in this round).
- ZAP active findings: 0 HIGH, 0 MED, 0 LOW. 1 cosmetic WARN
  (HTTP-only site, dev-only).
- Atomic commits in round: 1.
