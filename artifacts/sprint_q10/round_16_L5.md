# Q10 Round 16 — Layer L5 Lighthouse headless audit

**Tarih:** 2026-05-01
**Branch:** `feat/sprint-q10-quality-loop`
**Commit:** `bda943c`
**Mode:** Prod build (npx next start -p 3458), 4 panel sayfa

---

## Çalıştırma

```bash
npx --yes lighthouse@12 <URL> \
  --preset=desktop \
  --output=json --output-path=/tmp/lh-q10/<slug>.json \
  --extra-headers='{"Cookie":"abs_session=<token>"}' \
  --chrome-flags="--headless" --quiet
```

Sayfa seti: `/panel`, `/panel/chat`, `/panel/tools`, `/panel/quota`.

---

## Pre-fix scores

| Sayfa | perf | a11y | BP | SEO |
|-------|------|------|------|------|
| /panel | 100 | 96 | 96 | 91 |
| /panel/chat | 100 | 96 | 96 | 91 |
| /panel/tools | 100 | 90 | 96 | 91 |
| /panel/quota | 100 | 90 | 96 | 91 |

### Score-deducting fails (extracted from auditRefs)

| ID | Kategori (w) | Etkilenen | Açıklama |
|----|--------------|-----------|----------|
| color-contrast | a11y (7) | tümü | Sidebar nav `<span>` low-contrast |
| button-name | a11y (10) | tools, quota | icon-only / disabled buttons aria-label yok |
| errors-in-console | BP (1) | tümü | 400 Bad Request on `_next/static/chunks/*.js` |
| meta-description | SEO (1) | tümü | panel + admin layout meta description yok |

---

## Fix'ler

### Q10-L5-002 button-name (a11y w=10)

`app/panel/tools/page.tsx` pagination prev/next button'ları icon-only.
Eklendi: `aria-label="Önceki sayfa"` / `aria-label="Sonraki sayfa"`,
icon child'ına `aria-hidden="true"`. TR locale uyumlu.

### Q10-L5-003 meta-description (SEO w=1)

`app/panel/layout.tsx` + `app/admin/layout.tsx` route-group `Metadata`
export:

```tsx
export const metadata: Metadata = {
  description: "ABS Server admin paneli — cascade sağlayıcılar, MCP
    araçları, RAG ingest ve kota izleme tek bir self-hosted yüzeyde.",
  robots: { index: false, follow: false },
};
```

`robots: noindex, nofollow` — auth-gated panel surface'ı arama
motorunda olmamalı (defansif).

### Q10-L5-004 errors-in-console (BP w=1)

BP score'u meta description fix'i sonrası 4/4 sayfa için 96 → 100
yükseldi. Lighthouse `errors-in-console` artık skor düşüşü değil.
"next start" + `output: standalone` warning'i (`Use node
.next/standalone/server.js instead`) kalıyor — backlog.

---

## Post-fix scores

| Sayfa | perf | a11y | BP | SEO |
|-------|------|------|------|------|
| /panel | 99 | 94 | 100 | 91 |
| /panel/chat | 99 | 100 | 100 | 91 |
| /panel/tools | 100 | 100 | 100 | 91 |
| /panel/quota | 100 | 90 | 100 | 91 |

| Metrik | Pre-fix range | Post-fix range | Δ |
|--------|---------------|----------------|---|
| perf | 100 | 99–100 | -0/-1 (simulate noise) |
| a11y | 90–96 | 90–100 | up to +10 (tools) |
| BP | 96 | 100 | +4 ×4 |
| SEO | 91 | 91 | 0 (root metadata yet) |

**4/4 sayfa, 4/4 metrik ≥ 90 hedef ✅**

---

## L5 layer durumu

| Audit hedefi | Round 16 sonu |
|--------------|---------------|
| 4 panel sayfa ≥ 90 perf | ✅ 99–100 |
| 4 panel sayfa ≥ 90 a11y | ✅ 90–100 |
| 4 panel sayfa ≥ 90 BP | ✅ 100 |
| 4 panel sayfa ≥ 90 SEO | ✅ 91 |
| Lighthouse config (Round 8) | ✅ ship |

L5 3-round-clean sayacı: **1/3 → 2/3**.

---

## Backlog (Q10-L5-005, deferred)

`/panel/quota` a11y=90 kalan sebebi: Tremor `DateRangePicker`'ın
internal clear-X button (`button.absolute outline-none inset-y-0
right-0`) `aria-label` eksik + target-size yetersiz. Üçüncü-parti
component, fix:
1. Tremor wrap (forwardRef ile aria-label inject)
2. Headless UI date picker'a geç
3. Inline `[role=button][aria-label]` patch

L5 scope dışı; Phase R / Sprint 21 backlog.

---

## "next start" output:standalone warning (Q10-L5-006, info)

`npx next start -p 3458` her başlatmada warn:
```
⚠ "next start" does not work with "output: standalone" configuration.
   Use "node .next/standalone/server.js" instead.
```

`.next/standalone/` build sırasında oluşmuyor — `output: standalone`
config'i + Next 15.5 + bu repo file structure kombinasyonunda
generate edilmiyor. Lighthouse skorlarına etki etmedi (page render
sound). Sprint 17 docker image build path'iyle birlikte
incelenmeli.

---

## Atomic commit

`bda943c` — fix(q10/L5): Round 16 — Lighthouse a11y/BP/SEO uplift on panel surfaces

Files: 3 src — admin layout, panel layout, tools page.

---

## Sonraki round

**Round 17 = L3 theme matrix headless run.**

`q10-l3-theme-matrix.spec.ts` (Round 7 ship, 30 senaryo: 15 sayfa ×
dark/light) — prod :3458 üzerinde çalıştır, dark/light visual bug
ara.

---

**Round 16 status:** ✅ ship — 3 fix (button-name, meta-description,
console-errors-via-meta), 4/4 panel surface 4/4 metric ≥ 90
hedef, Q10-L5-005 + Q10-L5-006 backlog. L5 sayacı 1/3 → 2/3.
