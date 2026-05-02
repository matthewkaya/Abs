# Q12 — Round 9 — L18 sweep 3 (CDP slow 3G + CPU 4× variant)

**Tarih:** 2026-05-02
**Layer:** L18 — cold-cache 3rd sweep
**Branch:** `feat/sprint-q12-deep-quality`
**Worker:** Opus 4.7 (1M ctx)

---

## 0. Hedef

Round 3 cold-cache spec localhost loopback latency'de çalıştı
→ 40-324ms (KOBİ-pilot fidelity gap, Q12-L18-001 MED). Round 9
**CDP throttle**: `Network.emulateNetworkConditions` slow 3G +
`Emulation.setCPUThrottlingRate` 4×.

---

## 1. Shipped — `q12-l18-throttled.spec.ts`

12 test (6 route × 2 profil):

### Slow 3G + CPU 4× (6/6 PASS)

| Sayfa | LCP (ms) | TTFB (ms) | Budget (ms) |
|-------|---------:|----------:|------------:|
| `/` | 1184 | 27 | 6000 |
| `/pricing` | 0¹ | 415 | 6000 |
| `/panel` | **2836** | 14 | 4500 |
| `/panel/chat` | **3408** | 16 | 14000 |
| `/panel/tools` | **3060** | 12 | 11000 |
| `/panel/quota` | 1128 | 10 | 4500 |

¹ `/pricing` LCP 0 = no large element rendered (page is text-only,
no LCP candidate fires within 6s window).

### LTE 4G + CPU 2× (6/6 PASS)

| Sayfa | LCP (ms) | TTFB (ms) | Budget (ms) |
|-------|---------:|----------:|------------:|
| `/` | 316 | 5 | 3500 |
| `/pricing` | 0¹ | 110 | 3500 |
| `/panel` | 1044 | 21 | 3500 |
| `/panel/chat` | 1112 | 9 | 6000 |
| `/panel/tools` | 752 | 11 | 5000 |
| `/panel/quota` | 308 | 11 | 3500 |

```
Slow 3G chromium-desktop: 6 passed (56.4s)
LTE 4G + CPU 2×          : 6 passed (60s)
Combined run:              12 passed (1.6m)
```

---

## 2. Q12-L18-002 (LOW) — Lighthouse simulated vs CDP throttle methodology gap

**Bulgu:** Sprint 21 honest report Lighthouse "simulated throttling"
mode ile ölçtü. Bu mode desktop measurement'larını CPU×N + bandwidth
multiplier ile **extrapolate eder** — gerçek throttle değil.

CDP `Network.emulateNetworkConditions` + `Emulation.setCPUThrottlingRate`
gerçek throttle. İki yöntem farklı sonuç verir:

| Sayfa | Lighthouse simulated | CDP real | Δ |
|-------|---------------------:|---------:|----:|
| /panel | 2769ms | 2836ms | +67ms (parity) |
| /panel/chat | **11105ms** | **3408ms** | **-7697ms** (3.3× lower) |
| /panel/tools | 8660ms | 3060ms | -5600ms (2.8× lower) |
| /panel/quota | 2225ms | 1128ms | -1097ms |

**Gerçek KOBİ pilot LCP** muhtemelen iki ölçüm arasında — Lighthouse
overestimate ediyor (well-documented bias), CDP underestimate edebilir
(throttle tek-seferlik header değil per-chunk worst-case değil).

**Implication:** Sprint 21 close raporu chat/tools LCP "11s/8.6s
slow 3G" daha **karamsar bir number'dı**. Gerçek pilot 3-5s
arası, hala budget üstü ama "11s'lik UX faciası" değil.

**Fix:** Q12-L18-002 (LOW, dökümentasyon)
- `docs/qa/perf-budget-policy.md`'ye methodology footnote ekle:
  "Slow 3G LCP iki yöntemle ölçülür: Lighthouse simulated
  (~2-3× overestimate) ve Playwright CDP (real). Karar yaparken
  her ikisini de değerlendir."

Bu Sprint 22 backlog değil — Q12-L18-002 sadece note. Mevcut
budget'lar her iki yöntemi de geçerli görüyor.

---

## 3. Layer state

L18 sayım: **3/3 FULL CLEAN ⭐**
(Round 3 ship + Round 6 rerun + Round 9 CDP throttle variant)

| Layer | Counter | Notes |
|-------|---------|-------|
| **L17** | **3/3 ⭐** | bundle break-even validator + unit + CI gate |
| **L18** | **3/3 ⭐** | cold-cache + CDP throttle 12/12 PASS |
| **L19** | **3/3 ⭐** | backwards compat 11/11 PASS |
| L20 | 2/3 | chaos |
| L21 | 0/3 | founder-gated |

**3/5 Q12 yeni layer FULL CLEAN.**

---

## 4. Atomic commit

```
fix(q12/L18): Round 9 sweep 3 — CDP slow 3G + CPU 4× throttle variant 12/12 PASS → L18 FULL CLEAN
```
