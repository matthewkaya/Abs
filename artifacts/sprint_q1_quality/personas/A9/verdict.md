# A9 — RAG Researcher (PARTIAL PASS)

## Findings
- `/v1/rag/ingest` and `/v1/rag/query` endpoints exist in OpenAPI.
- Both gate behind OAuth bearer JWT (panel session cookie does NOT grant access — by design, T-005 separation).
- Live `POST /v1/rag/query` with panel session cookie → `401 missing_bearer_token` ✅ (auth gate works).
- Pytest cannot be exercised inside production-stripped backend container (no /tests dir, no pytest dep). Test suite ran during dev/CI per memory (1348 backend tests baseline).

## Verdict
- **Auth boundary** ✅ verified
- **Endpoint inventory** ✅ verified
- **Corpus ingest + golden top-1 retrieval** carry-over to Sprint Q2 (needs OAuth client credentials seed + tenant JWT minting in test harness)

Status: PARTIAL PASS — RAG path exists and is gated correctly. Full golden-dataset retrieval eval deferred.
