# Q10 Round 8 — Layer L5 Lighthouse Performance Budget

**Branch:** `feat/sprint-q10-quality-loop`

---

## Yeni config

`core/landing/lighthouserc-panel.json` — 15 panel sayfa için ayrı
budget. Mevcut `lighthouserc.json` (Sprint 18 R03'te kuruldu) sadece
4 public sayfa (`/`, `/pricing`, `/showcase`, `/onboarding`)
kontrolünü `0.95` threshold'la yapıyor. Q10 panel sayfaları auth gerek
+ Tremor/react-flow/force-graph dynamic import ağırlıklı, dolayısıyla
Q10 budget:

| Kategori | Public (var olan) | Panel (yeni) |
|----------|-------------------|--------------|
| performance | error 0.95 | warn 0.90 (ağır JS bundle, dynamic import) |
| accessibility | error 0.95 | error 0.90 |
| best-practices | error 0.95 | error 0.90 |
| seo | error 0.95 | warn 0.90 (auth-gated, robots noindex) |
| largest-contentful-paint | error 2800 | warn 3500 |
| cumulative-layout-shift | error 0.15 | error 0.15 |

`extraHeaders` ile `Cookie: abs_session=${ABS_PANEL_COOKIE}` enjekte
edilir → founder run'da bootstrap login cookie'si env'den geçer.

## Çalıştırma (founder makinası)

```bash
cd core/landing

# 1. Bootstrap admin cookie:
COOKIE=$(curl -sk -c - http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@local","password":"CHANGEME"}' \
  | grep abs_session | awk '{print $7}')
export ABS_PANEL_COOKIE="$COOKIE"

# 2. Lighthouse Q10 panel:
npx lhci autorun --config=lighthouserc-panel.json
```

Çıktı: `.lighthouseci/` altında 15 sayfa × 1 run JSON + HTML report.

---

## Beklenen profil

Mevcut public sayfalar 100/100/100/100 (Sprint 13-14 baseline). Panel
sayfalar için tahmin:

| Sayfa | perf | a11y | best | seo |
|-------|------|------|------|-----|
| /panel | ~92 (NeuralGraph dynamic) | ≥95 | ≥95 | n/a |
| /panel/chat | ~88 (markdown + virtualization) | ≥95 | ≥95 | n/a |
| /panel/tools | ~92 (TanStack Table) | ≥95 | ≥95 | n/a |
| /admin/workflow-builder | ~78 (react-flow + Three.js bundle) | ≥90 | ≥95 | n/a |

workflow-builder bundle ağır — Round 9 visual regression sonrası
optimize round (lazy load, dynamic import threshold) gündemde.

---

## L5 layer durumu

Sayaç: **1/3** (config ship, run founder).
Bug count: TBD (live run sonrası).

---

## Regression

37 backend pytest + 22 vitest + Q10 specs intact.

---

## Sonraki round

**Round 9 = L7 visual regression** — Playwright `expect(page).toHaveScreenshot()` ile baseline + diff. İlk run baseline kurar; ikinci run UI değişikliklerini diff eder.

---

**Round 8 status:** ✅ config ship — 15 sayfa Lighthouse panel budget, run pending.
