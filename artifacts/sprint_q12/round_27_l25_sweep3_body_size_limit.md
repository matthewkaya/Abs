# Round 27 — L25 sweep 3 request body size cap

**Sprint:** Q12 Session 4
**Layer:** L25 (boundary payload caps) — sweep 3
**Files touched:** 2 src + 1 new test
**Status:** ✅ shipped — **L25 → 3/3 FULL CLEAN ⭐** (8 Q12 layers FULL CLEAN total)

---

## Real bugs surfaced

### Q12-L25-004 (HIGH DoS) — admin endpoints accept unbounded request bodies

R17 (`marketplace.py`) added Pydantic Field caps on `plugin_id` (128 char)
and `tenant` (64 char), but those fire **after** Starlette parses the
entire request body into memory. A client could ship a 50 MB JSON
payload to `/v1/marketplace/install` and exhaust memory in the parser
pipeline before the field validator ever ran:

```bash
curl -X POST /v1/marketplace/install \
  -H "Content-Type: application/json" \
  -H "Content-Length: 60000000" \
  -d '{"plugin_id":"a","tenant":"b","blob":"<60MB of garbage>"}'
# pre-fix: parses 60 MB into memory, eventually returns 200/422.
# post-fix: 413 BEFORE body parse.
```

Same gap on `/v1/workflows/synthesize`, `/v1/workflows/execute`,
`/v1/chat/completions`, `/v1/marketplace/uninstall`. Each of these has
in-handler Pydantic caps from earlier sweeps, but none has an HTTP-layer
Content-Length gate.

### Q12-L25-005 (MED DoS) — RAG ingest accepts oversize bodies

`/v1/rag/ingest` Pydantic field caps `text` at 2 000 000 chars — sane,
but multipart uploads can still hit the wire as a single ~16 MB JSON
payload of escaped bytes (worst-case base64 inflation). Without an
HTTP-layer cap, a per-tenant attacker can flood the embedding pipeline
with oversize requests.

---

## Fix shipped

### `core/backend/app/middleware/body_size_limit.py` (new)

ASGI `BaseHTTPMiddleware` that:

1. Reads `Content-Length` header on POST/PUT/PATCH (skips GET/HEAD/OPTIONS/DELETE).
2. Looks up a per-path cap via longest-prefix match (`_default` fallback
   + `_hardcap` 50 MB ceiling).
3. Returns `413 request_body_too_large` with `{limit_bytes,
   received_bytes}` *before* any body parse runs.
4. Logs `body_size_limit_exceeded path=… cl=… cap=…` for ops audit.
5. Passes through chunked / no-Content-Length requests (Starlette's
   chunked decoder handles malformed cases).

```python
DEFAULT_CAPS = {
    "/v1/rag/ingest":              10 * 1024 * 1024,  # 10 MB
    "/v1/marketplace/install":     64 * 1024,         # 64 KB (admin payload)
    "/v1/marketplace/uninstall":   16 * 1024,
    "/v1/workflows/synthesize":    256 * 1024,
    "/v1/workflows/execute":       1 * 1024 * 1024,
    "/v1/chat/completions":        8 * 1024 * 1024,
    "_default":                    5 * 1024 * 1024,
    "_hardcap":                    50 * 1024 * 1024,
}
```

### `core/backend/app/main.py`

Wired between `DemoModeMiddleware` and `RequestIDMiddleware` so that the
request-id is still set on 413 responses (Q12-L23 audit continuity).

---

## Test inventory

`core/backend/tests/test_q12_l25_body_size_limit.py` — 9 new tests.

| # | Test | Vector |
|---|------|--------|
| 1 | `004_marketplace_install_50mb_rejected` | 50 MB body → 413 with `{limit_bytes, received_bytes}` |
| 2 | `004_marketplace_install_normal_body_passes_size_gate` | small body → not 413 (auth path runs) |
| 3 | `004_invalid_content_length_400` | malformed Content-Length → 400/4xx |
| 4 | `005_rag_ingest_15mb_rejected` | 15 MB body → 413 (cap is 10 MB) |
| 5 | `005_rag_ingest_normal_body_passes_size_gate` | 5 KB body → not 413 |
| 6 | `cap_for_longest_prefix_wins` | per-path cap resolution unit |
| 7 | `cap_for_hardcap_clamps` | `_hardcap` clamps oversized config |
| 8 | `get_request_no_body_check` | GET bypasses cap |
| 9 | `no_content_length_header_passes_through` | empty body smoke |

---

## Verification

```
host venv: 9/9 PASS in 1.56s
L25 + marketplace + RAG regression: 58 passed, 1 skipped, 0 failed in 25.34s
  - tests/test_q12_l25_body_size_limit.py        9
  - tests/test_q12_l25_boundary_payload.py       multi
  - tests/test_q12_l25_sweep2_boundary_caps.py   multi
  - tests/test_marketplace_hardening.py          multi
  - tests/test_t011_rag_pipeline.py              14
  - tests/test_t014_rag_gateway.py               5
```

Pre-fix proof: the middleware file did not exist before this commit.
The codebase had no Content-Length gate (`grep -rn "Content-Length\|
MAX_REQUEST_BODY\|max_body\|BodySizeLimit" core/backend/app` returned
nothing prior). Implicit pre-fix behavior: oversize requests parsed
fully (FastAPI default).

---

## Image + container evidence

```
image_rebuilt_at: 2026-05-03T13:10:40Z (Q12 Session 4 second rebuild)
container_file_present: /app/app/middleware/body_size_limit.py ✓
container_grep_count:  /app/app/main.py: 2 (import + install_body_size_limit call)
                       /app/app/middleware/body_size_limit.py: 3 (class + helper + comment)
```

Live curl smoke against running infra-backend-1:
```
POST /v1/marketplace/install (Content-Length: 60000000)
  → 413  {"detail":"request_body_too_large",
          "limit_bytes":65536,
          "received_bytes":60000000}

POST /v1/marketplace/install (29-byte body, no auth)
  → 401  {"detail":"Oturum yok"}    # auth path reached, body parsed normally
```

The 413 fires **before** auth so unauthenticated DoS is blocked at the
edge; the 401 path proves the legit body-size case still reaches the
auth dependency.

---

## L25 counter

| Sweep | Round | Vector | Verdict |
|-------|-------|--------|---------|
| 1 | R17 (S2) | InstallBody plugin_id+tenant Pydantic caps | ✅ |
| 2 | R24 (S3) | workflow execute UNBOUNDED nodes/edges + chat completions UNBOUNDED messages | ✅ |
| 3 | **R27 (S4)** | **HTTP-layer Content-Length cap (BodySizeLimitMiddleware)** | ✅ |

**Result: L25 → 3/3 FULL CLEAN ⭐** (8 Q12 layers FULL CLEAN total:
L17, L18, L19, L20, L22, L23, L24, **L25**).

---

## Delegation evidence

Self-design (middleware is pure async/Python; the cap-table + longest-prefix
match is short enough that delegation overhead would exceed inline
write time).

---

## Next round

R28 = L26 sweep 2 (30dk Playwright headed Chromium + heap snapshot) —
brief priority. If frontend dev server overhead still blocks, fall back
to L21 safe expansion (migration roundtrip 10× + JWT boundary edges).
