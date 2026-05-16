# WORKER_SPRINT_2N_3_HOT_PATCH_BRIEF — single-fix docs mike alias split

**Date:** 2026-05-16
**Sprint:** Sprint 2N.3
**Branch:** `feat/sprint-2n-3-hot-patch` (already cut, commit `3e41dc1` pre-staged)
**Predecessor:** Sprint 2N.2 (`v1.0.3`, docs run 25968243819 ❌ open)
**Successor:** v1.0.4 GA — docs site reflects v1.0.3 + v1.0.4 changelog

## Misyon

Sprint 2N.2 v1.0.3 push'unda Release + SBOM + CI Postgres + CodeQL hepsi
GREEN; tek açık `docs / build` job'unda `error: duplicated version and
alias`. Root cause: `MIKE_VERSION=latest` deploy step env'inde, deploy
komutu `mike deploy --update-aliases latest latest` oluyor — version
label ve alias aynı string, mike duplicate diye reddediyor. 2N.2 FAZ C
`mike delete latest` ekledi ama bu sadece alias'ı kaldırıyor; version
hâlâ kayıtlı kalıyor.

## Tek FAZ

### A. docs.yml — resolve-version step + alias split

`feat/sprint-2n-3-hot-patch` branch'inde **zaten commit** olarak hazır:
`3e41dc1 fix(docs): derive mike version from git ref (close v1.0.3
duplicated alias)`.

Patch'in özeti:

1. Yeni `Resolve mike version label` step:
   - `inputs.version` dolu ve `latest` değil → kullan
   - `event=push` + `ref_name=v*` → tag adını kullan (örn `v1.0.3`)
   - `event=release` → release tag
   - aksi → `main`
2. Deploy step env: `MIKE_VERSION: ${{ steps.mike_version.outputs.version }}`
3. Pre-delete stderr görünür (`|| echo "version not present"`); silent
   `|| true` kaldırıldı — auth/network hatası saklanmasın.
4. Deploy parametreleri: `mike deploy --update-aliases "${MIKE_VERSION}"
   latest` — version label artık alias'la çakışmıyor.

## Acceptance

| Madde | Hedef |
|-------|-------|
| docs run conclusion | success |
| `mike list` output | `v1.0.4 [latest, main, ...]` benzeri (version != alias) |
| docs.automatiabcn.com | `/v1.0.4/` ve `/` (alias `latest`) erişilebilir |
| Sprint 2N.2 + 2N.3 pytest baseline | 2171 / 0 / 24 (regression yok) |

## Push prosedürü (founder)

```
git fetch origin
git checkout main
git merge feat/sprint-2n-3-hot-patch --no-ff -m "merge: Sprint 2N.3 docs hot-patch"
# Tool-attribution scrub (recipe stays identical — strip any auto-added
# attribution trailers before tagging; founder pattern from 2026-05-16):
git filter-branch -f --msg-filter \
  '/path/to/founder/trailer-scrub.sh' \
  origin/main..HEAD
git tag -a v1.0.4 -m "ABS v1.0.4 — Sprint 2N.3 docs mike alias split (closes 2N.2 docs gap)"
git push origin main v1.0.4
```

Sonra `gh run watch` ile docs workflow GREEN bekle (~2dk). GREEN sonrası
`https://docs.automatiabcn.com/v1.0.4/` 200 OK doğrula.

## STOP criteria

- docs run conclusion ≠ success → log dump + iterate (yeni patch, yeni tag)
- Release / SBOM / CI Postgres / CodeQL workflow regression
- Pytest regression
- Any tool-attribution trailer leaks past the scrub gate → ship-blocker,
  sprint geri çekilir (see founder memory: trailer-ban policy from
  2026-05-09 + 2026-05-16 enforcement).

## Pre-read

- `_agent-tasks/SPRINT_2N_2_REPORT.md` — neden 2N.3 var
- `_agent-tasks/PRODUCTION_READY_CERTIFICATE_v1.0.3.md` — v1.0.3 sertifikası
- `.github/workflows/docs.yml` — pre-patch hali main'de
- docs run 25968243819 — fail kanıtı
- `feat/sprint-2n-3-hot-patch:3e41dc1` — patch içeriği

Tool-attribution ban is active (founder enforcement 2026-05-09 +
2026-05-16). Pre-commit grep gate before every staged commit:

```
# Replace BANNED_PATTERN with the founder-maintained pattern list.
git diff --staged | grep -iE "${BANNED_PATTERN}"
```

→ boş döndüğünde commit yap. Pattern listesi founder memory'de.
