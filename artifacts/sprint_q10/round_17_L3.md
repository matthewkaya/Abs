# Q10 Round 17 — Layer L3 theme matrix headless run

**Tarih:** 2026-05-01
**Branch:** `feat/sprint-q10-quality-loop`
**Mode:** Standalone server isolated to `/tmp/q10-standalone/`,
PORT=3458.

---

## Çıkarım

`q10-l3-theme-matrix.spec.ts` (Round 7 ship, 30 senaryo: 15 sayfa ×
dark/light) bu round'da **canlı çalıştı**. İlk attempt 30/30 fail,
çünkü prod build artifact'i koruma altında değildi. Harness fix +
re-run: 30/30 PASS, 0 dark/light regression.

---

## Q10-L3-001 — Standalone build isolation (HIGH harness, fix)

**Severity:** HIGH (test infrastructure — engelleyiciydi).

**Kök neden:** `next start` + `output: standalone` çatışması:
1. `npm run build` → `.next/standalone/server.js` üretir, **ama
   `.next/standalone/.next/static/` ve `public/` kopyalanmaz**
   (Next.js 15 davranışı, dokümante).
2. `next start` standalone modunda çalışmaz (warn + 400 chunks).
3. `node .next/standalone/server.js` çalıştırılırken paralel `next
   dev --port 3000` projemizdeki `.next/` dizinini sürekli yazıyor →
   `.next/standalone/` rebuild thrash → server ölü dosyalara
   refer ediyor → 400 Bad Request her chunk için.

**Tek build içinde 4 sürede `.next/standalone/` kayboldu** (file
mtime 19:45 olduğu halde sonraki `ls` boş döndü). Dev server
hot-rebuild'inin yan etkisi.

**Fix (harness, kod değil):**

```bash
# Build → snapshot → run from /tmp (dev server'dan izole)
rm -rf .next /tmp/q10-standalone
npm run build
cp -r .next/standalone /tmp/q10-standalone
cp -r .next/static /tmp/q10-standalone/.next/
cp -r public /tmp/q10-standalone/
HOSTNAME=localhost PORT=3458 ABS_BACKEND_URL=http://localhost:8000 \
  node /tmp/q10-standalone/server.js
```

`/tmp/q10-standalone/` dev mode HMR'ından izole. Static + public
manuel kopyalandı (Next.js dokümante davranış).

Bu hand-off **Round 16 Lighthouse run'ında da gerekli** (geriye
dönük: Round 16 tek-process çalıştığı için patlamadı, ama paralel
playwright workers + dev mode = thrash).

---

## Run sonuçları

```
PLAYWRIGHT_BASE_URL=http://localhost:3458 \
  ABS_PANEL_EMAIL=admin@demo-acme.com \
  ABS_PANEL_PASSWORD=DemoPass2026! \
  npx playwright test q10-l3-theme-matrix --project=chromium-desktop \
    --reporter=line --workers=2

[30/30] q10-l3 workflow · light
30 passed (14.5s)
```

| Senaryo | dark | light |
|---------|------|-------|
| panel | ✅ | ✅ |
| chat | ✅ | ✅ |
| tools | ✅ | ✅ |
| providers | ✅ | ✅ |
| pipelines | ✅ | ✅ |
| rag | ✅ | ✅ |
| marketplace | ✅ | ✅ |
| quota | ✅ | ✅ |
| graph | ✅ | ✅ |
| settings | ✅ | ✅ |
| audit | ✅ | ✅ |
| users | ✅ | ✅ |
| meetings | ✅ | ✅ |
| transcription | ✅ | ✅ |
| workflow-builder | ✅ | ✅ |

Spec 3 invariant doğruluyor:
1. response status ∈ {200, 302, 304} (auth bounce safe)
2. `data-page` selector visible
3. `documentElement.classList` `dark` (dark theme) / not `dark`
   (light theme) — next-themes class strategy uyumu
4. Console error filter (HARMLESS allowlist sonrası empty)

---

## L3 layer durumu

| Audit hedefi | Round 17 sonu |
|--------------|---------------|
| spec ship | ✅ (Round 7) |
| live run dark+light | ✅ 30/30 PASS |
| 0 console error (HARMLESS allowlist sonrası) | ✅ |
| dark/light class transition | ✅ |
| Q10-L3-001 standalone harness | ✅ documented |

L3 3-round-clean sayacı: **1/3 → 2/3**.

---

## Atomic commit

Yalnız docs (kod fix yok — harness fix shell prosedürüydü, source
kalıcı değişiklik gerekmedi).

---

## Sonraki round

**Round 18 = L2 integration enrich.**

Mevcut 7 contract test (Round 6) yeterince yüzeyi kaplamıyor.
Hedef: RAG ingest+query roundtrip + marketplace install→sandbox
roundtrip ekle (real httpx, mock backend hand-off).

---

**Round 17 status:** ✅ ship — Q10-L3-001 harness fix dokümante,
30/30 dark+light PASS, 0 visual regression. L3 sayacı 1/3 → 2/3.
