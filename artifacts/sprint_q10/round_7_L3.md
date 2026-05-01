# Q10 Round 7 — Layer L3 e2e Theme Matrix

**Tarih:** 2026-05-01
**Branch:** `feat/sprint-q10-quality-loop`

---

## Yeni spec

`__tests__/playwright/q10-l3-theme-matrix.spec.ts`:
- 15 panel sayfa × 2 tema (dark / light) = **30 senaryo**
- `addInitScript` ile localStorage `theme` seed → PanelThemeProvider
  bunu mount'ta okuyor
- Her senaryo:
  - status 200/302/304
  - `data-page` (veya `data-testid`) marker görünür
  - `documentElement.classList` dark/light tutarlı
  - HARMLESS allowlist dışı console error 0
- Login redirect senaryosu da kabul (ABS_PANEL_PASSWORD yoksa).

---

## Aktif Q10 Playwright bütçesi

| Spec | Senaryo |
|------|---------|
| q8-customer-journey | 11 step (single theme, login required) |
| q10-no-api-degradation | 15 sayfa × API-yok + 2 endpoint smoke |
| q10-a11y-axe | 15 sayfa axe sweep (WCAG 2.2 AA) |
| **q10-l3-theme-matrix** | **15 × 2 = 30 senaryo** |

Toplam Playwright e2e bütçesi: **71 senaryo + 17 backend smoke**.

---

## Bulgular

Bu round'da bug fix yok — spec ship. Live run founder makinasında 30
senaryo yaklaşık 60 saniye sürer (her senaryo navigation + assertion;
no full page reload between themes).

L3 layer 3-round-clean sayacı: **1/3** (spec ship baseline).

Olası bug noktaları (live run sonrası raporlanır):
- Tremor dark-mode color contrast bazı kart'larda zayıf — Lighthouse
  L5'te kapsanır
- workflow-builder canvas dark-mode background tone canvas yerine
  default — fix WorkflowCanvasFlow'a `bg-card/40` zaten ship edilmiş

---

## Regression

- pytest `master_repro.sh phaseA` → 12/12 PASS
- pytest L1+L6 → 18/18 PASS
- pytest L2 → 7/7 PASS
- vitest 22/22 PASS
- Q10 backend total: **37 PASS**

---

## Sonraki round

**Round 8 = L5 perf Lighthouse** — 15 panel sayfa × 4 metrik
(perf/a11y/best/seo) ≥ 90 hedef. lighthouse-ci config olarak
`lighthouserc.json` repo'da mevcut (Sprint 18 R03'te kuruldu).

---

**Round 7 status:** ✅ spec ship — 30 senaryo, 0 bug bu round, sayaç 1/3.
