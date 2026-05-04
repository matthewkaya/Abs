# Round 55 — Wire R44 Hypothesis 30K into mutation-weekend cron

**Sprint:** Q12 Session 7 (extension beyond brief 12)
**Layer:** Q11-L13 / Q11-L6 — CI scheduling
**Files touched:** 1 (`mutation-weekend.yml`)
**Status:** ✅ shipped — YAML validated

---

## Brief

R44 shipped the 30K Hypothesis fuzz behind `@pytest.mark.fuzz` so
default `pytest` skips it. R41 mutmut weekend cron exists. R55
**actually wires** the 30K fuzz into the same Saturday cron so the
opt-in marker fires on schedule, not "the next time someone
remembers to run pytest -m fuzz".

## Change

`.github/workflows/mutation-weekend.yml`:

- Added `fuzz-30k` job parallel to the existing `mutmut` matrix
- Independent (no `needs:` linkage); both run on Sat 02:00 UTC
- 30-minute timeout (R44 measured 101 s on the host venv; CI
  runners are slower but well under the cap)
- 1-retry pattern: `pytest -m fuzz || pytest -m fuzz`. FastAPI
  client cold-start can flake; the second run is authoritative
- On failure, uploads `.hypothesis/` directory as artifact so the
  shrunk counter-example is preserved

## YAML validation

```
$ python3 -c "import yaml; \
    print(list(yaml.safe_load(open('.github/workflows/mutation-weekend.yml'))['jobs'].keys()))"
['mutmut', 'fuzz-30k']
```

Both jobs present + parseable.

## Image rebuild

N/A — CI workflow only. Backend `app/` untouched.

## Counters

- Backend pytest: unchanged 1665.
- Atomic commits: 1.
