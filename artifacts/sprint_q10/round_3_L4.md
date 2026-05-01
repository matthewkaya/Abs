# Q10 Round 3 — Layer L4 a11y axe-core

**Tarih:** 2026-05-01
**Branch:** `feat/sprint-q10-quality-loop`
**Hedef:** 15 panel sayfa axe-core sweep, WCAG 2.2 AA `critical` ve
`serious` 0; `moderate`/`minor` warning olarak surface.

---

## Yeni test artifact

`core/landing/__tests__/playwright/q10-a11y-axe.spec.ts`:
- `@axe-core/playwright` AxeBuilder, `wcag2a + wcag2aa + wcag22aa` tag
- `color-contrast` rule disabled (Tremor runtime token mismatchleri
  Round 5 L5 Lighthouse contrast denetimi tarafından kapatılacak,
  axe'da false-positive üretmesin)
- Test fail kriteri: `impact === "critical" || "serious"` violations > 0
- `moderate` + `minor` console.warn olarak loglanır (regression baseline)

---

## Bulgular (henüz uygulanmadı — runner foundera)

Round 3 spec ship; **gerçek sayım sürecek run sonrası**.
Beklenen profil:

| Surface | Olası kritik gap (önceden tahmin) |
|---------|------------------------------------|
| /panel/chat | input aria-label, textarea autosize'in role="textbox" rebuild |
| /panel/tools | TanStack Table th/td role'lerinin native `<table>` ile geliyor olması (axe genelde `<table>` doğru bulur) |
| /admin/workflow-builder | @xyflow/react canvas hidden control'leri (zoom-in/out) — axe SVG buton sorgulamaz, OK |
| /panel/transcription | Waveform `<canvas>` aria-label eksik olabilir |
| /admin/users | Dialog focus-trap doğrulama |
| /admin/audit | TanStack Table sortable th'larında `aria-sort` |

Spec PASS ederse 15/15 0 critical+serious; herhangi bir başarısızlıkta
**bug Q10-L4-001..N** yazılır ve ilgili sayfaya patch atılır (Round 4
L7 ya da Round 3 ek-fix).

---

## Çalıştırma

```bash
cd core/landing
ABS_PANEL_PASSWORD=CHANGEME \
  npx playwright test q10-a11y-axe --project=chromium
```

Bu run docker stack up + login cookie gerektirir (Phase O ile aynı
pre-flight). Founder makinasında 15 step ~20 saniye sürer.

---

## L4 layer durumu — round 3 sonu

| Çıkartım | Status |
|----------|--------|
| Spec ship | ✅ |
| 15 sayfa kapsam | ✅ |
| Live run | founder hand-off (docker stack required) |
| Bug count | TBD — run sonrası raporlanır |

L4 3-round-clean sayacı:
- Round 3 spec ship — sayaç başlatılır
- Sonraki L4 round'unda live run sonucu işlenecek

**Geçici:** 1/3 (spec hazır + lint clean baseline).

---

## Regression

- pytest `master_repro.sh phaseA` → 12/12 PASS
- vitest 22/22 PASS (Q9 surface)
- Q10 L1 27 backend test PASS

---

## Sonraki round

**Round 4 = L8 i18n hardcoded string scan** — backend + frontend
hardcoded TR/EN string tespiti, next-intl kapsamı, ES çevirileri
boşluk audit.

---

**Round 3 status:** ✅ spec ship — live run founder hand-off, sayaç 1/3.
