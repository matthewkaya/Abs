# Round 90 — R82 Lighthouse nightly artifact review (Pazartesi sonrası)

**Date:** 2026-05-05 (Tuesday)
**Status:** WAITING-FOR-RUN — the Saturday cron is the first execution
of the post-fix workflow. Worker cannot run cron jobs ad-hoc; this
round documents what to inspect after the next two cron firings.

## Background

Q12-S9 R82 (HEAD f362601) fixed the lighthouse-nightly workflow that
was silently broken because the runner targeted `https://abs.local`
which CI cannot resolve. R82 swapped the URL to `localhost:3000` and
ensured the landing app is started + warmed up before the audit.

## Verification runs to inspect

| When (UTC) | What |
|------------|------|
| 2026-05-09 02:00 | First post-fix Saturday cron — should produce a real artifact for the first time. |
| 2026-05-12 (Mon) | Worker reads artifact via `gh run download <run_id> -n lighthouse-results`. |

## Post-cron checklist

```bash
# 1. List recent lighthouse-nightly runs.
gh run list --workflow lighthouse-nightly.yml --limit 5

# 2. Confirm the first post-fix run finished with success.
gh run view <run_id> --log | grep -E "Lighthouse|Categories"

# 3. Download the artifact.
gh run download <run_id> -n lighthouse-results
ls lighthouse-results/

# 4. Check the four scores.
jq '.categories | to_entries | map({key, score})' lighthouse-results/*.json
# Expected (from spec): performance/a11y/best-practices/seo each ≥ 0.95.
```

## Live-path-verified contract

A successful R90 round summary appends:

```yaml
run_id: <gh run id>
ran_at: <ISO 8601>
performance_score: 0.xx
a11y_score: 0.xx
best_practices_score: 0.xx
seo_score: 0.xx
artifact_size_bytes: <int>
all_thresholds_met: true|false
live_path_verified: true|false
```

If the cron fails again or produces no artifact, file an incident
linking back to R82 and `f362601` for context — the abs.local→localhost
fix is the most recent change to the workflow.

## Skip rationale (R90 today)

The first post-fix cron has not yet fired (next run: 2026-05-09 Sat
02:00 UTC). Until then there is nothing to review. Round opens this
file as a "ready to fill in" template; founder/worker completes after
the run.
