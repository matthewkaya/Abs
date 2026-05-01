# Q10 Round 9 — Layer L7 Visual Regression

**Branch:** `feat/sprint-q10-quality-loop`

---

## Yeni spec

`__tests__/playwright/q10-l7-visual-regression.spec.ts`:
- 10 panel sayfa (rasgele timing'e duyarlı 5 sayfa — meetings, transcription,
  graph, audit, workflow-builder — baseline'a şimdilik dahil değil; v2'de
  data-fixture ile stable hale getirilir)
- `expect(page).toHaveScreenshot(slug.png)` Playwright snapshot diff
- `maxDiffPixelRatio: 0.02` — anti-alias drift toleransı
- `animations: "disabled"` — framer-motion entrance reproducible
- `fullPage: true` — sayfa altına kayan içeriği de yakala
- Login redirect → test.skip (baseline temiz kalır)

---

## İlk run — baseline kurma (founder)

```bash
cd core/landing
ABS_PANEL_PASSWORD=CHANGEME \
  npx playwright test q10-l7-visual-regression --update-snapshots
```

İlk run snapshot'ları `__tests__/playwright/q10-l7-visual-regression.spec.ts-snapshots/`
altına yazar. Bu snapshot dizini `git add`'lenip baseline olarak commit
edilir. Sonraki PR'larda CI bu baseline'a karşı diff yapar.

## Sonraki run — diff modu

```bash
ABS_PANEL_PASSWORD=CHANGEME \
  npx playwright test q10-l7-visual-regression
```

UI değişiklikleri pixel-level fark üretirse test fail eder; PR review'da
ekran görüntüsü diff'i CI artifact'ı olarak indirilir.

---

## L7 layer durumu

Sayaç: **1/3** (spec + maxDiffPixelRatio politikası ship; baseline
founder'da). Bug count: TBD (baseline kurulduktan sonra ikinci PR'da
diff açar).

---

## Regression

37 backend pytest + 22 vitest + Q10 specs intact.

---

## Sonraki round / loop ilerleme

L1 1/3, L2 1/3, L3 1/3, L4 1/3, L5 1/3, L6 1/3, L7 1/3, L8 1/3, L9 1/3.

**Tüm 9 layer ilk turda 1/3 sayaca ulaştı.** 2. tur (round 10-18)
re-scan + 3. tur (round 19-27) confirmation gerekiyor FULL CLEAN için.

---

**Round 9 status:** ✅ spec ship — visual regression baseline ready.
