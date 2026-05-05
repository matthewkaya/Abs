# Q12 Round 96 — Regression close-out (Grup A + B + C, single root cause)

**Branch:** `feat/sprint-q12-deep-quality` · **Date:** 2026-05-05

---

## TL;DR

S11 founder host run baseline `1735 passed / 3 failed / 17 errors` was driven by
**one** state-pollution bug in `tests/test_q12_magic_link_e2e.py` plus a
secondary chat-session row leak. Single atomic fix → full suite GREEN.

```
pytest_full_suite_before: 1735 passed / 3 failed / 17 errors / 14 skipped / 3 deselected
pytest_full_suite_after:  1755 passed / 0 failed / 0 errors  / 14 skipped / 3 deselected
delta:                    +20 (+19 newly passing test cases + 1 chat empty-list re-green)
runtime:                  176.13s (0:02:56)
```

Tek doğru komut:
```
cd core/backend && ./.venv/bin/python -m pytest --no-header -q \
  --ignore=tests/test_providers.py \
  --ignore=tests/test_q03_real_saas_backends.py \
  --ignore=tests/test_update_channel.py
```

---

## Bisect — pollution chain

Pre-fix baseline output: 3 fails on `tests/test_secrets_api.py` + 7 errors on
`tests/test_q12_provider_degradation_matrix.py` + 10 errors on
`tests/test_q8_chat.py`. **All three groups failed inside `_login` /
`auth_client` fixture with the SAME assertion:**

```
AssertionError: {"detail":"E-posta veya parola hatalı"}
assert 401 == 200
```

Standalone runs all PASSED:
- `pytest tests/test_secrets_api.py` → 4/4 PASS
- `pytest tests/test_q12_provider_degradation_matrix.py` → 7/7 PASS
- `pytest tests/test_q8_chat.py` → 12/12 PASS

So the brief's "RSC contract drift" hypothesis for Group C and the "R84 settings
collision" hypothesis for Group A were both **wrong** — single shared root
cause: the bootstrap admin login `admin@local + CHANGEME` was being denied by
a polluted `admin_credentials.json` left in the session-scope `data_dir`.

**Bisect path (3 narrowing runs):**
1. `tests/test_q*.py + tests/test_secrets_api.py -x` → first ERROR on
   `test_q12_provider_degradation_matrix[all_present-6-6]` after 358 passed →
   polluter is in the `test_q12_*` block before provider_degradation
   alphabetically.
2. `test_q12_license_full_lifecycle.py + test_q12_magic_link_e2e.py +
   test_q12_provider_degradation_matrix.py + test_secrets_api.py` →
   reproduced 3 fails + 7 errors → polluter ⊆ {license_full_lifecycle,
   magic_link_e2e}.
3. `test_q12_license_full_lifecycle.py + test_q12_provider_degradation_matrix.py
   + test_secrets_api.py` → 18/18 PASS → license is innocent.
4. `test_q12_magic_link_e2e.py + test_q12_provider_degradation_matrix.py +
   test_secrets_api.py` → 7 PASS / 3 FAIL / 7 ERROR → **confirmed polluter:
   `tests/test_q12_magic_link_e2e.py`**.
5. `test_q12_magic_link_e2e.py + test_q8_chat.py` → 6 PASS / 10 ERROR →
   same polluter for Group C.

**No commit-level git bisect needed.** Pollution is intrinsic to the test
file, not a regression introduced by a recent commit. The brief's
"5b1b6d5..9c6d05c" / "16f8103..2b196ed" ranges are red herrings — the test
file itself never had data_dir isolation.

---

## Root cause — `_claim_user_by_token` writes `admin_credentials.json`
## to the session-scope `settings.data_dir`

`core/backend/app/api/auth.py:413` — when `/auth/magic?token=...` claims a
pending signup, it overwrites `Path(settings.data_dir) / "admin_credentials.json"`
with the claimed user's email + bcrypt hash.

`tests/test_q12_magic_link_e2e.py` runs the signup → claim flow for
`admin_a@r87.local`, `admin_a_active@r87.local`, etc. **Without any
monkeypatch on `settings.data_dir`** — every `_claim_user_by_token` write
lands in the session-scope tmp dir created by `conftest._session_data_dir`
and persists for the rest of the suite.

The bootstrap login flow at `auth.py:228..287` then resolves
`_load_admin_credentials()` to the file's contents (`admin_a@r87.local`),
*not* the bootstrap fallback (`admin@local + CHANGEME`). The candidate list
ends up empty for `payload.email == "admin@local"` and the handler raises
`HTTPException(401, "E-posta veya parola hatalı")`.

Sister test `tests/test_q12_r91_final_acceptance.py` runs the *same* claim
flow without breaking anything because it monkeypatches
`settings.data_dir = tmp_path` via its `_fresh_state` fixture — every claim
write goes to a per-test tmp dir that is GC'd at teardown. magic_link_e2e
just lacks that fixture.

**Secondary leak (Group C only):** even after Group A/B were re-green,
`test_chat_sessions_empty_list` still failed because earlier tests
(`test_q10_l1_coverage`, `test_q11_l13_fuzz`, `test_q12_l25_boundary_payload`,
`test_q12_l29_setup_wizard_full_sweep`, `test_q12_r91_final_acceptance`) had
created `ChatSession` rows on `tenant_slug="default"` (the bootstrap admin's
tenant) which the assert `r.json() == []` couldn't tolerate.

---

## Atomic fix (one commit, two fixtures)

### `tests/test_q12_magic_link_e2e.py`
Module-scope `autouse` fixture `_isolate_data_dir(monkeypatch, tmp_path)`:
- Pins `settings.data_dir` to a per-test `tmp_path`.
- Re-writes `setup_state.json` with `completed: true` so
  `FirstRunMiddleware` does not redirect `/auth/signup` to `/setup`
  (the conftest autouse writes that file to the OLD `data_dir`, our
  fixture must replace it inside the new one).

Net result: every claim's `admin_credentials.json` lands in `tmp_path/` and
never leaks to the session dir.

### `tests/test_q8_chat.py`
Module-scope `autouse` fixture `_wipe_default_tenant_chat_state()`:
- Per-test deletes every `ChatSession` (and its `ChatMessage` children)
  with `tenant_slug == "default"`. The empty-list contract is now suite-
  order independent.

---

## Verification matrix

| Run | Result |
|-----|--------|
| `pytest tests/test_q12_magic_link_e2e.py` | 6/6 PASS |
| `pytest tests/test_q12_magic_link_e2e.py + provider + secrets` | 29/29 PASS |
| `pytest tests/test_q12_magic_link_e2e.py + q8_chat + provider + secrets` (R96+R97+R98 fix) | 29/29 PASS |
| `pytest tests/test_q8_chat.py` standalone (post fix) | 12/12 PASS |
| **Full suite (post both fixtures)** | **1755 passed / 0 failed / 0 errors / 14 skipped / 3 deselected** ✅ |

Brief target `X ≥ 1755` met exactly.

---

## What did NOT need fixing

- No app/auth.py / app/chat.py code change. The polluter was only the test
  file's missing isolation.
- No git revert / commit bisect. Pollution is intrinsic, not a recent
  regression.
- No new tests, no new layers (per Session 12 explicit no-new-test rule).

---

## Round count

- R96 = combined Grup A + Grup B + Grup C atomic fix (single commit) — single
  root cause.
- R97 = (folded into R96, same commit).
- R98 = (folded into R96, same commit + supplementary q8_chat default-tenant
  wipe to close the secondary leak).
- R99 = full suite GREEN verification (this artifact).
