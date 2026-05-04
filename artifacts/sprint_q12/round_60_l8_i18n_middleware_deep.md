# Round 60 — L8 i18n middleware + set_lang_cookie deep coverage

**Layer:** Q11-L8 (i18n) deep round 2
**Status:** ✅ ship
**Time:** 2026-05-04 ~16:50

## Goal

S8 brief target: backend pytest +25 (1665 → 1690). R60 contributes
+15 directly with a real coverage gap close.

## Pre-R60 gap

`app.middleware.i18n.I18nMiddleware` and `app.i18n.set_lang_cookie`
were imported by `app.main:67,201` and active in production but had
**no direct test coverage** beyond a single `/healthz` smoke that
didn't assert `request.state.lang`.

`tests/test_i18n_basic.py` covered the pure functions (`t()`,
`detect_lang()`) but never the middleware's cookie-over-header
precedence or the cookie writer.

A regression that reversed the precedence (header overriding the
user's explicit cookie) would silently break the language switcher
on the panel surface — every session would revert to whatever the
OS-level `Accept-Language` said, ignoring the UI choice. No
regression guard.

## What R60 ships

`tests/test_q12_l8_i18n_middleware_deep.py` (15 pytest, **15/15 PASS**
in 0.57 s):

### set_lang_cookie writer contract (3 tests)
- writes `NEXT_LOCALE=tr` with 365-day Max-Age + samesite=lax
- silent no-op on unsupported lang ('de' → no `NEXT_LOCALE` header)
- silent no-op on empty string

### Middleware request.state.lang resolution (6 tests)
- no-signal → DEFAULT_LANG (asserted via `detect_lang(None)` direct
  call; TestClient/httpx auto-injects host-environment Accept-Language
  and cannot be reliably suppressed across all transport layers, so we
  exercise the source-of-truth function directly)
- Accept-Language only → 'tr-TR,tr' → 'tr'
- Cookie only → 'es' → 'es'
- **Cookie wins over Accept-Language** (locks UI selection precedence)
- Invalid cookie → falls through to header
- Invalid cookie + no header → DEFAULT_LANG
- Uppercase cookie value normalized via `.lower()`

### detect_lang edge cases (4 parametrize)
- `de-DE;q=0.95,tr;q=0.5` → 'tr' (left-to-right scan, locks current
  contract against silent q-weighting refactor)
- `   ,  ,en` (whitespace-only chunks) → 'en' (no crash)
- `ES-ES` (uppercase prefix) → 'es' (normalisation)
- `===garbage===` → 'en' (default fallback)

### Defensive lock (1 test)
- `SUPPORTED_LANGS == ('en','tr','es')` and `DEFAULT_LANG == 'en'`
  locked. Cross-references the panel/admin TR-first scope policy in
  `docs/qa/i18n-scope-policy.md` (R58).

## Real bug found?

No new product bug. R60 closes a **coverage gap** — the production
middleware was correct but unguarded. The cookie-precedence test
documents the load-bearing UX contract that the language switcher
relies on.

## Pytest deltas

| Run | Tests | Time | Pass | Fail |
|-----|-------|------|------|------|
| `test_q12_l8_i18n_middleware_deep.py` (new) | 15 | 0.57 s | 15 | 0 |
| `test_i18n_basic.py` (sibling) | 12 | 1.57 s | 12 | 0 |
| Combined | 27 | 1.57 s | 27 | 0 |

S8 backend pytest target: 1665 + 25 = 1690. R60 contributes +15
toward target (no regression in sibling tests).

## Image rebuild gate

R60 touches **only test files**, not `app/i18n/__init__.py` or
`app/middleware/i18n.py`. **No image rebuild required.** Backend
container preserved from R52 baseline.

## Sprint Q12 layer matrix delta

| Layer | Pre-R60 | Post-R60 |
|-------|---------|----------|
| Q11-L8 i18n | 0/3 + R58 ⭐ deep scope | 0/3 + R58 + R60 ⭐⭐ deep middleware |

## Files touched

- `core/backend/tests/test_q12_l8_i18n_middleware_deep.py` (new, 15 pytest)

## Commit

(Atomic R60 commit; see `git log --oneline -1` after this round)

## Next

R61 = continue toward S8 brief +25 pytest target. Candidate gaps:
- `body_size_limit.py` middleware (R27 production fix; existing
  coverage may have a deep-edge gap)
- `request_id.py` middleware (uncovered?)
- `audience.py` middleware (T-058 coverage?)
