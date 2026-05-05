# Q12 Session 12 — REGRESSION CLOSE-OUT (real MÜHÜR)

**Date:** 2026-05-05 · **Branch:** `feat/sprint-q12-deep-quality` · **HEAD before S12:** `38b3500` · **HEAD after R100:** `b779a91`

Two atomic commits:

| Commit | Round(s) | Focus |
|--------|----------|-------|
| `dbaeca8` | R96–R99 | magic-link `data_dir` isolation + chat default-tenant wipe → full suite GREEN |
| `b779a91` | R100 | tester docs align with regression-free state |

---

## Pre-state vs post-state

```
pytest_full_suite_before_S12: 1735 passed / 3 failed / 17 errors / 14 skipped / 3 deselected
pytest_full_suite_after_R99:  1755 passed / 0 failed / 0 errors  / 14 skipped / 3 deselected
delta:                        +20 (3 fail → pass + 17 error → pass)
runtime:                      176.13s (0:02:56)
```

Brief target `X ≥ 1755` met exactly.

Canonical command (single source of truth, also pinned in
`docs/qa/founder_action_items.md` §0):

```
cd core/backend
./.venv/bin/python -m pytest --no-header -q \
  --ignore=tests/test_providers.py \
  --ignore=tests/test_q03_real_saas_backends.py \
  --ignore=tests/test_update_channel.py
```

---

## Single root cause (all 20 fail/error)

`tests/test_q12_magic_link_e2e.py` ran the signup → `/auth/magic` claim
flow without isolating `settings.data_dir`. `auth.py` line 413
(`_claim_user_by_token`) writes `admin_credentials.json` into
`Path(settings.data_dir)`. With no monkeypatch, every claim leaked into
the session-scope tmp dir created by `conftest._session_data_dir`.

Subsequent tests posting `admin@local + CHANGEME` to `/auth/login` got
401 because `_load_admin_credentials()` now returned the file's leaked
email (`admin_a@r87.local`), shadowing the bootstrap fallback at
`auth.py:71`.

**Why 3 groups all failed at the same spot:**
- `test_secrets_api.py::_login` calls `/auth/login` directly →
  AssertionError on `assert r.status_code == 200`.
- `test_q12_provider_degradation_matrix.py::admin_client` fixture calls
  `/auth/login` → 401 → fixture setup raises → all 7 parametrize cases
  ERROR before reaching the test body.
- `test_q8_chat.py::auth_client` fixture calls `/auth/login` → 401 →
  fixture setup raises → all 10 chat tests ERROR.

Sister test `test_q12_r91_final_acceptance.py` runs the SAME claim
flow without leaking, because its `_fresh_state` fixture
`monkeypatch.setattr(settings, "data_dir", str(tmp_path))`.
magic_link_e2e simply lacked that fixture.

---

## Bisect chain (no commit-level bisect needed)

The brief's 5b1b6d5..9c6d05c / 16f8103..2b196ed ranges were red herrings.
Pollution is intrinsic to the test file, not a regression introduced by
a recent commit. Bisect by file pair:

1. `tests/test_q*.py + tests/test_secrets_api.py -x` → first ERROR on
   `test_q12_provider_degradation_matrix[all_present-6-6]` after 358
   passed → polluter ⊆ test_q12_* alphabetically before
   provider_degradation.
2. `license_full_lifecycle + magic_link + provider + secrets` →
   reproduces 3 fail + 7 error → polluter ⊆ {license, magic_link}.
3. `license_full_lifecycle + provider + secrets` → 18/18 PASS →
   license is innocent.
4. `magic_link + provider + secrets` → 7 PASS / 3 FAIL / 7 ERROR →
   confirmed polluter = `test_q12_magic_link_e2e.py`.
5. `magic_link + q8_chat` → 6 PASS / 10 ERROR → same polluter for
   Group C.

---

## Atomic fix (R96 + R98, single commit `dbaeca8`)

### `tests/test_q12_magic_link_e2e.py`

Module-scope autouse `_isolate_data_dir(monkeypatch, tmp_path)` pins
`settings.data_dir` per test and re-writes `setup_state.json` with
`completed: true` so `FirstRunMiddleware` does not redirect `/auth/signup`
to `/setup` (the conftest autouse writes setup_state.json to the OLD
`data_dir`, our fixture must replace it inside the new one).

### `tests/test_q8_chat.py`

Module-scope autouse `_wipe_default_tenant_chat_state()` deletes
leftover `ChatSession` + `ChatMessage` rows on `tenant_slug="default"`
before each test. Earlier tests
(`test_q10_l1_coverage`, `test_q11_l13_fuzz`, `test_q12_l25_boundary_payload`,
`test_q12_l29_setup_wizard_full_sweep`, `test_q12_r91_final_acceptance`)
seed default-tenant sessions; without per-test wipe the empty-list
contract fails at the first assert.

**No app code changed. No git revert. No new tests, no new layers.**

---

## R100 — tester docs alignment

Two surfaces updated to reflect S12 reality and prevent S11-style
selective-subset evidence:

- `docs/qa/tester_handoff_checklist.md` — HEAD `dbaeca8`, full-suite
  count `1755 / 0 / 0`, S11 retraction note, canonical command pinned in
  Status block, sign-off forbids selective subset evidence.
- `docs/qa/founder_action_items.md` — new §0 mandatory pre-flight gate
  (full backend suite must be GREEN before any other step), retraction
  note, sign-off requires founder to paste the canonical command's last
  line into the tag commit.

---

## Memory & feedback

- New memory: `feedback_full_suite_mandatory.md` — Q12 S5/S10/S11/S12
  4th-repeat rule. "MÜHÜRLÜ" iddiası ANCAK canonical command 0 fail / 0
  error sonrası yazılabilir.
- Indexed in `MEMORY.md`.

---

## What is NOT shipped (per Session 12 explicit no-go list)

- L21 destructive drill ACTUAL — founder approval gate (still pending)
- Mutmut local actual — founder approval gate (still pending)
- Pilot/market/outreach — out of session scope
- New tests / new layers — explicit S12 brief rule

---

## Sprint Q12 round count

100 atomic rounds shipped (R1–R100). Backend pytest **1755 PASS** on the
canonical full-suite command, 0 fail / 0 error.

**Tester teslimat eşiği gerçek MÜHÜRLÜ** behind the founder's §0 host
verification + 7 action items.
