# Sprint 21 — Perf Architecture Audit Summary

**Branch:** `feat/sprint-21-perf-architecture`
**Tetikleyici:** Q11-L5-001 backlog (chat LCP 9.9s + tools LCP 8.6s under CPU 4× / slow 3G).
**Hedef:** Chat + Tools LCP ≤2.5s slow 3G + CPU 4× throttle. Q10/Q11 0 regression.

---

## Faz çıktıları

| Faz | İçerik | Sonuç |
|-----|--------|-------|
| A | Bundle baseline analiz | top 5 fix targets ranked |
| B | Tremor + Recharts lazy via next/dynamic | /panel 924K→520K (-44%), /panel/quota 711K→509K (-28%) |
| C | Chat client + react-markdown lazy | /panel/chat 854K→367K (-57%) |
| D | NeuralGraph + CommandPalette ssr:false dynamic | semantik defer (TBT/parse win, byte parity) |
| E | Lucide tree-shake | already correct (~64K total) — refactor SKIP |
| F | next/font subset + display:swap | T-R03'te kuruldu — refactor SKIP |
| G | Image optimize | public/ empty, no raster — refactor SKIP |
| H | Verification + this summary | regression PASS / **LCP target NOT achieved** |

---

## Bundle delta tablosu

| Route | Baseline | Faz B+C+D | Δ |
|-------|---------:|----------:|----:|
| /panel | 924K | 520K | **-44%** |
| /panel/chat | 854K | 367K | **-57%** |
| /panel/quota | 711K | 509K | **-28%** |
| /panel/tools | 613K | 614K | parity |
| /admin/workflow-builder | 582K | 583K | parity |
| /admin/providers | — | 530K | (heavyweight provider grid) |

---

## Lighthouse throttled (CPU 4× / slow 3G 400 KB/s) — gerçek sonuç

| Sayfa | Baseline LCP | Sprint 21 LCP | Δ | Hedef ≤2500ms |
|-------|-------------:|--------------:|----:|:-------------:|
| /panel | 2275ms | 2769ms | +494ms | ❌ over budget |
| /panel/chat | 9875ms | **11105ms** | +1230ms | ❌ **REGRESSION** |
| /panel/tools | 8652ms | 8660ms | parity | ❌ over budget |
| /panel/quota | 2200ms | 2225ms | parity | ✅ |

| Sayfa | Baseline perf | Sprint 21 perf | Δ |
|-------|--------------:|---------------:|----:|
| /panel | 69 | 61 | -8 |
| /panel/chat | 62 | 60 | -2 |
| /panel/tools | 61 | 60 | parity |
| /panel/quota | 74 | 73 | parity |

**Hedef başarısız:** Chat + Tools + Panel LCP throttled budget aşıldı.

---

## Kök neden — code-splitting under heavy throttle

Sprint 21 yaklaşımı (Faz B + C + D) bundle'ı küçültüp `next/dynamic`
ile tabakalı (cascaded) load yaptı. Hızlı network'te bu net win
sağlardı (paralel parallel chunk fetch). **Slow 3G + CPU 4× altında
ters etki:**

- 400ms RTT × her round trip → ekstra round trip = +400ms LCP
- /panel/chat artık 3 round trip:
  1. page.tsx (3K dynamic shim) → 400ms
  2. ChatClient.tsx chunk → 400ms (depends on round 1)
  3. chat-stream + components (react-markdown) → 400ms (depends on round 2)
- 3 × 400 = ≈1200ms ekstra → tam +1230ms gözlemlenen LCP regression

Bundle byte tasarrufları gerçek (-487K /panel/chat) ama throttled
network'te bytes != speed. Bottleneck round-trip latency.

---

## Q11-L5-001 — gerçekçi mimari yol

Throttled LCP ≤2.5s için Sprint 21 code-split yaklaşımı yetersiz.
Sprint 22 brief'i için aşağıdaki strateji önerilir:

1. **React Server Components (RSC)** — chat/tools listing + LCP
   candidate'ı server-render et. Skeleton client'ta değil, HTML'de
   ship et. (Single round trip; LCP fires at FCP+small delta.)
2. **Streaming SSR** — react-markdown rendering server-side
   (limited by Markdown spec but doable with `@mdx-js/react` or
   server-side `marked` + sanitize).
3. **Edge Runtime** — Caddy + Next edge runtime ile RTT 400ms→100ms
   (CDN POP).
4. **Service Worker prefetch** — `/panel/*` route gruplarını
   pre-cache.

Bu Sprint 21 scope'unun dışında — yeni sprint gerektirir.

---

## Regression — Q8 + Q10 + Q11 0 fail

```
backend pytest:     89/89 PASS
playwright (chrome): 122/122 PASS
  q10-no-api-degradation 17
  q10-l3-theme-matrix    30
  q10-l7-visual          10
  q11-l11 cross-browser   5
  q11-l12 responsive     60
```

Sprint 21 functional regression-safe.

---

## Atomic commit zinciri

```
cc2ab7c  docs(s21/A): bundle analysis baseline
22b47ea  perf(s21/B): tremor + recharts lazy load
03f1ca2  perf(s21/C): chat client lazy + react-markdown defer
4829122  perf(s21/D): NeuralGraph + CommandPalette dynamic ssr:false
60725e9  docs(s21/E): lucide tree-shake correct — refactor skip
76638e8  docs(s21/F): font config production-grade — refactor skip
bb08c66  docs(s21/G): no raster images — refactor skip
[this]   docs(s21/H): re-baseline + honest perf assessment
```

---

## Sprint 21 kapanış kararı

**Bundle reduction shipped (real win for fast-network users).**
**LCP throttled hedefi başarılamadı** — code-splitting yaklaşımı
slow-3G + CPU-4× kombinasyonunda ters etki yaptı.

**Q11-L5-001 backlog'da kalıyor** — Sprint 22 RSC/SSR mimarisi
gerektiriyor (founder approval gerekli, scope büyük).

**Sprint 21 değer:**
- Fast network'te per-route bytes 28-57% düştü
- Bundle analyzer reproducible (artifacts/sprint_21/bundle_*.html)
- 4 atomic perf commit, regression-safe
- Sprint 22 için temiz başlangıç noktası
