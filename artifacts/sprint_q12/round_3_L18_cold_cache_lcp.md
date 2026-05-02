# Q12 — Round 3 — L18 cold-cache first-visit LCP

**Tarih:** 2026-05-02
**Layer:** L18 — cold-cache first-visit (Q12 yeni)
**Branch:** `feat/sprint-q12-deep-quality`
**Worker:** Opus 4.7 (1M ctx)

---

## 0. Hedef

Sprint 21 honest report Lighthouse throttled altında ölçtü. Mevcut
Playwright spec'leri ise her test'i warm-cache + zero-network-latency
çalıştırıyor — KOBİ pilot ilk demo açışı (cold-cache + ofis fiber
~50ms RTT) test edilmemiş. Q12-L18 bu boşluğu kapatır.

---

## 1. Çözüm — `q12-l18-cold-cache.spec.ts`

15-route × per-page LCP budget:

| Sayfa | Auth | Budget (ms) | Cold LCP (ms) | FCP (ms) | TTFB (ms) | Verdict |
|-------|------|------------:|--------------:|---------:|----------:|---------|
| `/` | — | 3500 | 220 | 220 | 61 | ✅ |
| `/pricing` | — | 3500 | 44 | 44 | 11 | ✅ |
| `/showcase` | — | 3500 | 40 | 40 | 7 | ✅ |
| `/onboarding` | — | 3500 | 312 | 32 | 4 | ✅ |
| `/panel` | ✓ | 4500 | 96 | 48 | 13 | ✅ |
| `/panel/chat` | ✓ | 5500 | 324 | 40 | 10 | ✅ |
| `/panel/tools` | ✓ | 5500 | 168 | 44 | 22 | ✅ |
| `/panel/quota` | ✓ | 4500 | 40 | 40 | 12 | ✅ |
| `/panel/meetings` | ✓ | 4500 | 56 | 56 | 10 | ✅ |
| `/panel/transcription` | ✓ | 4500 | 40 | 40 | 9 | ✅ |
| `/admin/marketplace` | ✓ | 4500 | 80 | 40 | 8 | ✅ |
| `/admin/providers` | ✓ | 4500 | 44 | 44 | 8 | ✅ |
| `/admin/workflow-builder` | ✓ | 5500 | 48 | 48 | 15 | ✅ |

**13/13 PASS.** Spec özellikleri:
- Per-test `browser.newContext({ serviceWorkers: "block" })` — SW yok
- `clearCookies()` + ardından sadece `abs_session` JWT inject
- `extraHTTPHeaders: Cache-Control: no-cache, no-store, must-revalidate`
- `PerformanceObserver` ile LCP/FCP/TTFB toplama
- `waitUntil: "networkidle"` ardından 3 sn settle window

---

## 2. Q12-L18-001 (MED) — cold-cache + warm-network = yetersiz fidelity

**Bulgu:** Localhost loopback latency ≈0ms olduğundan cold-cache LCP
40-324ms arasında — Sprint 21 throttled ölçümü (2275-11105ms) ile
karşılaştırılabilir değil. Spec geçerli **bir koruma sağlıyor**
(cold-cache regression detector) ama KOBİ-pilot fidelity için
yetersiz.

**Üç çözüm seçeneği:**

1. **Playwright + CDP throttle:** `client.send("Network.emulateNetworkConditions", {...})`
   ile slow 3G emulation. Per-test cost +5-10sn, total ~3 dk.
2. **Lighthouse CI cold-cache mode:** `lighthouserc.json`'a
   `chromeFlags: ["--disable-cache","--disable-application-cache"]`
   ekle. Sprint 21'in mevcut throttled run'ı zaten cold çalıştırıyor.
3. **k6 + headless network shaping:** prod-like network simülasyonu.

**Öneri:** Sprint 22 RSC migration sonrası tekrar gözden geçir.
Mevcut spec **regression guard** olarak yeterli — 5500ms üstüne
çıkma engelleniyor (chat). Sprint 21 honest result `/panel/chat`
warm 11105ms zaten budget ihlal ediyor; cold-cache spec aynı
darboğazı yakalayacak (network throttle eklendiğinde).

---

## 3. Şu an shipped olanlar

- `core/landing/__tests__/playwright/q12-l18-cold-cache.spec.ts`
  (15 route, 13 test runnable + 2 fallback skipped if cookie missing)
- Per-page LCP budget sözleşmesi
- Auth cookie loader (`/tmp/q12_cookie.txt` Netscape format,
  `#HttpOnly_` prefix-aware)
- Cold-cache enforcement (SW block + Cache-Control header)

## 4. Sprint 22 backlog (L18 follow-up)

- `q12-l18-throttled.spec.ts` — CDP slow 3G + 4× CPU throttle
- Lighthouse CI cold-cache mode (zaten enabled mi audit et)
- LCP budget revisit (Sprint 22 RSC migration sonrası)

---

## 5. Atomic commit

```
fix(q12/L18): Round 3 Q12-L18-001 cold-cache LCP spec + budget table
```

---

## 6. Layer state

L18 sayım: **1/3**. Spec runnable + 13/13 PASS. Throttled fidelity
gap (Q12-L18-001 MED) Sprint 22 backlog. 2 round daha (regression
+ throttled variant) FULL CLEAN için gerekli.
