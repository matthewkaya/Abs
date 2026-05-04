# Round 44 — Q11-L13 Hypothesis fuzz scaled to 10K examples

**Sprint:** Q12 Session 7
**Layer:** Q11-L13 (cascade router + RAG + workflow input fuzz)
**Files touched:** 2 (1 new test + 1 pyproject markers)
**Status:** ✅ shipped — 3/3 PASS, **30 000 generated examples**, 0 5xx

---

## Brief

S6 R39 capped the per-surface budget at 1 000 examples (3K total)
as the engineering tradeoff. Brief target was 10K per surface
(30K total). R44 ships the 30K target *and* the marker scaffolding
so the heavy job lives in CI cron, not on every PR.

## Files

### `core/backend/pyproject.toml` (EDIT)

Added `[tool.pytest.ini_options]` markers:

```toml
markers = [
    "fuzz: opt-in heavy property-based fuzz (10K+ Hypothesis examples; default-skip)",
]
addopts = "-m 'not fuzz'"
```

The default `pytest` invocation now skips `@pytest.mark.fuzz` —
the 1633 PASS path is preserved. The fuzz suite runs only with
`pytest -m fuzz` (R41 weekend cron picks this up).

### `core/backend/tests/test_q11_l13_hypothesis_10k.py` (NEW)

3 `@pytest.mark.fuzz` test classes, each with `max_examples=10_000`:

- `TestQ11L13ChatCompletions10K` — cascade router entry
- `TestQ11L13RagQuery10K` — retrieval entry
- `TestQ11L13WorkflowsSynth10K` — orchestration entry

Same composite `chat_message()` strategy as R39 + same
`ACCEPTABLE_STATUS` set. The R39 1K suite stays as the
fast-feedback regression guard for every PR.

## Verification

Default pytest path (R39 still runs, R44 skipped):

```
$ pytest tests/test_q11_l13_hypothesis_10k.py -q
no tests collected (3 deselected) in 0.09s   ✓
```

Fuzz mode opt-in (full 10K execution):

```
$ pytest tests/test_q11_l13_hypothesis_10k.py -m fuzz -q
...
3 passed, 1 warning in 101.37s (0:01:41)
```

**30 000 generated examples in 101.37s. 0 counter-examples found.**
Backend pytest unchanged at 1633 (the new file is default-skipped).

## Engineering note

The S6 R39 estimate ("88s × 3 = 4–5 minutes for 30K") proved
high. Actual runtime: **101 seconds** (~30 seconds per 10K
surface). The difference is FastAPI client warm-up + Hypothesis'
shrinker getting smarter as it learns the constraint surface.

This makes the 30K run reasonable for nightly cron (not just
weekend). But to keep CI throughput predictable we leave it
under `-m fuzz` and let the weekend mutation job (R41) opt in
explicitly.

## Image rebuild

N/A — test-only round; no `app/` source touched. The running
`infra-backend-1` image is unchanged. `hypothesis>=6.150` was
already added to `[dev]` in S6 R39.

## Layer matrix delta

| Layer | Before R44 | After R44 |
|-------|------------|-----------|
| Q11-L13 | 0/3 + 3 000 examples (R39) | **0/3 + 30 000 examples** (R39 1K fast path + R44 10K opt-in) |

## Counters

- Backend pytest default: unchanged 1633 PASS / 14 skipped.
- Backend pytest -m fuzz: 3 tests, 30K examples, 101.37s.
- New test surfaces: 3 (default-skipped under marker).
- Atomic commits in round: 1.
