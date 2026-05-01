# Task 018 — Landing Page Premium (Hero + Pricing + FAQ + Lighthouse 90+)

**Status:** READY (Worker)
**Tahmini süre:** 3-4 saat
**Bağımlı task'lar:** 003 (landing iskelet), 011 (3 SKU + Stripe Checkout), 017 (billing + customer portal)
**Hedef sonuç:** `core/landing/` Next.js 15 sitesini paid customer kabul edebilir, profesyonel görünümlü, Lighthouse 90+ skorlu marketing site'a dönüştür.

---

## 0. Bağlam

003'te Next.js 15 + React 19 + Tailwind 3 iskeleti kuruldu (`core/landing/`). Hero + 8 Feature + Pricing + FAQ + Footer mevcut ama:
- Premium SVG illustrations yok (placeholder div'ler)
- Pricing CTA "Buy" butonu Stripe Checkout endpoint'ine bağlanmış değil
- Beta tester quotes / social proof yok
- FAQ içerik thin (8 soru var ama derinlikli değil)
- Lighthouse skorları test edilmemiş (image optimization, lazy loading, font preload eksik)
- Customer portal "Manage subscription" linki yok
- 11 adımlı setup wizard demo screencast yok (Loom embed placeholder)
- Mobile responsive denenmedi

017 customer portal endpoint hazır (`POST /v1/billing/portal`), 011 checkout endpoint hazır (`POST /v1/checkout/create-session`). Landing bunları call edecek.

---

## 1. Amaç (DoD)

- [ ] Hero section premium SVG illustration (inline, dark+light theme)
- [ ] Pricing CTA → fetch `/v1/checkout/create-session` + redirect `checkout_url`
- [ ] FAQ 12 soru (8 mevcut + 4 yeni: Anthropic TOS, vault, refund, GDPR)
- [ ] Beta tester quote section (3 quote, ScreenshotPicture-ready placeholder)
- [ ] Demo screencast section (3-min Loom iframe placeholder + URL env var)
- [ ] Customer portal link header'da "Manage" buton (modal: email gir → POST /v1/billing/portal → redirect)
- [ ] Footer: legal entity (Automatia BCN), GDPR + Privacy Policy + Terms link
- [ ] Lighthouse Mobile + Desktop ≥ 90 (LCP, FID, CLS, TTI)
- [ ] 12 yeni component test (Vitest + React Testing Library)
- [ ] 5 smoke evidence (Lighthouse JSON, screenshot mobile/desktop, network HAR)
- [ ] Backend hâlâ 292 test yeşil (regression yok)

---

## 2. Modüller

### Modul A — Hero + SVG Illustration
- `core/landing/components/hero.tsx` refactor — premium SVG (izometrik küp, brand color #1e57ac)
- Animated gradient background (CSS, no JS)
- 2 CTA: "Start Free Trial" (→ /pricing scroll) + "Watch Demo" (→ #demo scroll)
- 1 component test

### Modul B — Pricing CTA Live Integration
- `core/landing/components/pricing.tsx` refactor — 3 SKU card (self-host, team-5, team-10)
- "Buy" buton onClick → fetch backend + redirect
- Email input modal before checkout (validation EmailStr regex)
- Loading state + error toast
- 4 component test (mock fetch, valid email, invalid email, network error)

### Modul C — FAQ Genişletme
- `core/landing/components/faq.tsx` extend — 8 → 12 soru
- Yeni: Anthropic TOS uygunluk, sops/age vault, refund 7 gün, GDPR data residency
- Accordion animation (no JS, pure CSS `:checked + label` pattern)
- 2 test (item open, only one open at a time)

### Modul D — Social Proof + Demo
- Yeni `core/landing/components/quotes.tsx` — 3 testimonial card
- Yeni `core/landing/components/demo.tsx` — Loom iframe (env: `NEXT_PUBLIC_DEMO_LOOM_URL`)
- Placeholder image (`/demo-thumbnail.png`) + lazy load
- 2 test

### Modul E — Customer Portal Modal
- Yeni `core/landing/components/manage-modal.tsx` — header "Manage" link
- Modal: email input → POST /v1/billing/portal → redirect
- 404 → "Lisans bulunamadı, satın alma sayfasına git"
- 3 test (valid → redirect, 404, network error)

### Modul F — Footer + Legal
- `core/landing/components/footer.tsx` extend — Automatia BCN entity, links: /privacy, /terms, /refund
- Yeni `core/landing/app/privacy/page.tsx` (~400 kelime privacy policy)
- Yeni `core/landing/app/terms/page.tsx` (~600 kelime terms)
- Yeni `core/landing/app/refund/page.tsx` (~300 kelime refund policy)
- 3 test (page render, links exist)

### Modul G — Lighthouse Optimization
- `next.config.ts` — `images.formats: ['image/avif', 'image/webp']`
- Font preload (Inter / JetBrains Mono)
- Critical CSS inline (Next.js automatic)
- Lazy load below-the-fold (Loom iframe, footer images)
- Run `npx lighthouse http://localhost:3001 --output=json --output-path=/tmp/abs-018-smoke/evidence/lighthouse.json --preset=desktop`
- Mobile preset ayrı çalıştır

---

## 3. Test Stratejisi

| Dosya | Test sayısı |
|---|:-:|
| `__tests__/hero.test.tsx` | 1 |
| `__tests__/pricing.test.tsx` | 4 |
| `__tests__/faq.test.tsx` | 2 |
| `__tests__/quotes.test.tsx` | 1 |
| `__tests__/demo.test.tsx` | 1 |
| `__tests__/manage-modal.test.tsx` | 3 |
| `__tests__/footer.test.tsx` | 3 |
| **TOPLAM** | **15** |

Vitest + React Testing Library. Mock `fetch` ile backend call'ları sahte.

Backend regression: `cd core/backend && .venv/bin/pytest -q` → 292 PASS (017'den).

---

## 4. Smoke Evidence (`/tmp/abs-018-smoke/evidence/`)

1. `01_lighthouse_desktop.json` — Lighthouse desktop run (≥90 LCP/FID/CLS)
2. `02_lighthouse_mobile.json` — Lighthouse mobile run
3. `03_screenshot_desktop.png` — 1920×1080 home page
4. `04_screenshot_mobile.png` — 375×812 home page
5. `05_network_har.json` — DevTools HAR export (yükleme zamanları)

---

## 5. Adım Adım

```
1.  cd core/landing && npm install (yeni dependencies: @testing-library/react, vitest)
2.  Modul A: hero.tsx + SVG + 1 test
3.  Modul B: pricing.tsx + email modal + 4 test
4.  Modul C: faq.tsx 12 item + 2 test
5.  Modul D: quotes + demo + 2 test
6.  Modul E: manage-modal + 3 test
7.  Modul F: footer + privacy/terms/refund pages + 3 test
8.  Modul G: next.config.ts optimize + Lighthouse run
9.  npm run dev (port 3001) → background
10. Lighthouse desktop + mobile çalıştır, evidence kaydet
11. Screenshot desktop + mobile (Playwright headless)
12. HAR export
13. backend pytest regression check
14. summary.md yaz, completed/'a taşı
```

---

## 6. DoD Checklist

```
[ ] 7 modül A-G tamam
[ ] 15 component test yeşil (vitest)
[ ] backend pytest 292 yeşil (regression yok)
[ ] Lighthouse desktop ≥90 LCP/FID/CLS/TTI
[ ] Lighthouse mobile ≥85 (mobile biraz daha düşük tolerans)
[ ] 5 smoke evidence dosyası valid
[ ] Privacy/Terms/Refund sayfaları render
[ ] Customer portal modal çalışıyor (mock backend)
[ ] Pricing CTA Stripe Checkout endpoint'e bağlı (mock fetch)
[ ] 018-landing-page-premium-summary.md yazıldı
[ ] Task completed/'a taşındı
```

## 7. Worker Notları

1. Backend dokunulmayacak — sadece `core/landing/` altında çalış.
2. Loom URL env var (`NEXT_PUBLIC_DEMO_LOOM_URL`) — kullanıcı sonra dolduracak, şimdilik placeholder.
3. Tailwind class'ları için `core/backend/`'in panel CSS pattern'inden esinlen (premium-card, premium-grid).
4. Image asset'leri `core/landing/public/` altına; `landing-home.png` mevcut hero arka plan değil, demo ekran görüntüsü.
5. Lighthouse `--throttling-method=devtools` desktop, `--preset=mobile` mobile.
6. Vitest config `vitest.config.ts` yoksa oluştur (`@vitejs/plugin-react`).
7. Privacy/Terms/Refund metinleri için `ask "..." qwen32b` kullan, GDPR + EU compliance ton.
8. Manage modal: email → POST + redirect window.location, modal kapanmaz (loading state göster).
