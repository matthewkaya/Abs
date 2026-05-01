# Task 003 — Landing: Next.js Site + Stripe Checkout

## Bağlam

Müşteri journey'sinin **ilk adımı**: `abs.automatiabcn.com` subdomain'ine gelir → ürünü görür → pricing'i okur → "Buy Now" basar → Stripe Checkout → ödeme başarılı → 002'deki webhook tetiklenir → lisans key email'e gider.

Bu task o **frontend + Stripe Checkout button** kısmını kurar. Backend (webhook + license generator) 002'de hazır.

**Bağlı docs:**
- `docs/research/landing-onboarding.md` — sayfa yapısı, hero varyantları, features, pricing, FAQ
- `docs/research/competitive-analysis.md` — farklarımız (8 madde)
- `docs/vision.md` — tek sayfalık değer önermesi
- `docs/design-decisions.md` § 2 (marka: Automatia ABS), § 8-12 (pricing, Stripe, Automatia entity)

**Kaynaklar:** SERVER'da landing kodu **YOK**. Scratch. Referans: Next.js 15 docs + Stripe Checkout Session API + Tailwind.

## Giriş (Mevcut Durum — 002 sonrası)

- `core/backend/` — FastAPI backend + licensing + webhook (çalışıyor, Docker'da `abs.local:443`)
- Landing için **ayrı proje** — `core/landing/` altına Next.js
- Domain: `abs.automatiabcn.com` (DNS setup henüz yok, ama kod production-ready olsun)
- Automatia BCN Stripe hesabı mevcut (004'te webhook bağlanacak)

## Beklenen Çıktı

### 1. Next.js proje scaffold (`core/landing/`)

- [ ] `core/landing/package.json` — Next.js 15, React 19, Tailwind 4, shadcn/ui, `@stripe/stripe-js`
- [ ] `core/landing/next.config.ts`
- [ ] `core/landing/tsconfig.json`
- [ ] `core/landing/tailwind.config.ts`
- [ ] `core/landing/app/layout.tsx` — Metadata (SEO: title, description, OG image), Automatia logo, dark mode
- [ ] `core/landing/app/page.tsx` — Ana sayfa (hero + features + pricing + FAQ + footer)
- [ ] `core/landing/app/globals.css`

### 2. Bileşenler (`core/landing/components/`)

- [ ] `Hero.tsx` — Başlık + alt metin + CTA button + opsiyonel demo video placeholder
- [ ] `Features.tsx` — 6-8 madde (araştırmadan: 75 MCP, 13 pipeline, 6 provider, RAG, Judge, workflow, docker 15dk, dogfooding)
- [ ] `Pricing.tsx` — 3 kart (Self-Host $299, Maintenance +$49/yr, Cloud $79/ay "Yakında")
- [ ] `FAQ.tsx` — 6-8 soru (Anthropic TOS, kurulum, refund, support, data privacy, güncelleme)
- [ ] `Footer.tsx` — Automatia logo + sosyal linkler + legal (Terms, Privacy) placeholder
- [ ] `CheckoutButton.tsx` — Stripe Checkout Session başlatan button (API route `/api/checkout` çağırır)

### 3. API route (Next.js App Router)

- [ ] `core/landing/app/api/checkout/route.ts` — POST endpoint
  - Body: `{ tier: 'self-host' | 'maintenance' | 'team-5' | 'team-10' }`
  - Stripe Checkout Session oluştur (line_item: Stripe Product ID env'den)
  - Success URL: `/success?session_id={CHECKOUT_SESSION_ID}`
  - Cancel URL: `/`
  - Customer email collect: true (required for license delivery)
  - Metadata: `{ tier, seat_count }`
- [ ] `core/landing/app/success/page.tsx` — "Satın alma tamam, lisans key email'inize gelecek" + "Kurulum rehberine git" butonu

### 4. İçerik (Türkçe)

**Hero:**
```
Başlık: Claude Pro $20 aboneliğinizle $1000+/ay enterprise seviyesinde çalışın.
Alt metin: Automatia ABS — kendi sunucunuzda, 75 MCP tool + 6 sağlayıcı cascade + Türkçe kalite pipeline'ı. Kurulum 15 dakika. Tek seferlik $299.
CTA: 14 Günlük Demoyu İndir  /  Fiyatlandırmayı Gör
```

**Features (8 madde — araştırmadan):**
1. 75 MCP tool — hazır kurulu, uzatılabilir
2. 13 kalite pipeline — qual-code, qual-tr, qual-analysis, judge
3. 6 sağlayıcı cascade — Anthropic + Groq + Cerebras + Gemini + CloudFlare + Cohere
4. Symbol-aware RAG — 10K+ sembol, callsite graph
5. Senior Judge — AST + LLM birleşik kalite skoru
6. Türkçe kalite pipeline'ı — benzerlerinde yok
7. 15 dakika kurulum — Docker Compose tek komut
8. Dogfooding — kurucu 6 aydır bizzat kullanıyor

**Pricing (3 kart):**
| Kart | Fiyat | Özellikler |
|---|---|---|
| Self-Host Lifetime | $299 one-time | Ömür boyu + 1yr update + tüm özellikler + 1 lisans |
| + Maintenance | $299 + $49/yıl | Sürekli update + öncelikli destek |
| Managed Cloud | $79/ay — **Yakında** | Kurulum yok, bizim hostlarız |

+ Team Pack: 5 seat -%20 ($1.196), 10 seat -%30 ($2.093), 25+ custom

**FAQ (6-8 soru):**
1. **Anthropic TOS ihlali mi?** Cevap: API key commercial terms pay-per-use — legal %100. OAuth token (Pro plan) değil.
2. **Kurulum teknik mi?** Cevap: Docker Compose tek komut, 15 dk, SSH bilen herkes yapar.
3. **Lisans kayıp olursa?** Cevap: Email + panel'de saklı, recover edilebilir.
4. **İade garantisi?** Cevap: 14 gün no-questions-asked Stripe refund.
5. **Destek?** Cevap: Email (14 gün response), maintenance ile 48 saat.
6. **Kod Anthropic'e mi gidiyor?** Cevap: Evet — Claude API kullanımının doğal parçası. ABS sunucumuza **gelmez**, müşteri kendi Anthropic hesabıyla konuşur.
7. **Neden Automatia?** Cevap: 6 ay dogfooding + Türkçe-first yaklaşım + self-host bağımsızlık.
8. **Güncelleme nasıl?** Cevap: `docker-compose pull && up -d` tek komut.

### 5. Styling

- **Tailwind 4** + **shadcn/ui** component library
- **Automatia logosu** — Automatia BCN'den al (beyaz SVG, kod içinde inline veya `public/logo.svg`)
- Dark mode default (dev/tech kullanıcı)
- Responsive (mobile-first)
- Tipografi: Inter (sans) + JetBrains Mono (code snippet)
- Renk: Automatia BCN mevcut paletinden (varsa kullan, yoksa slate/zinc + brand accent)

### 6. SEO + Metadata

- `metadata` export: title, description, keywords
- OG image: `public/og.png` (1200×630 placeholder — ileride tasarlanır)
- `robots.txt`
- `sitemap.xml`

### 7. Test

- [ ] `core/landing/__tests__/Hero.test.tsx` — Hero render + CTA button click
- [ ] `core/landing/__tests__/CheckoutButton.test.tsx` — Stripe Checkout Session mock → redirect URL
- [ ] Vitest veya Jest + React Testing Library

## Kısıtlar

- ❌ SERVER klasörüne dokunma
- ❌ Fake metrikler ("AI maliyetlerinizi %80 azaltın" gibi **kullanma** — research'te tespit edilmiş halüsinasyon)
- ❌ "SOTA", "en güçlü", "revolutionary" marketing dili — **dürüst + sayısal değer önermesi**
- ❌ Stripe Product ID hardcode — env'den oku
- ✅ Next.js 15 App Router
- ✅ React Server Components (Hero, Features static RSC)
- ✅ CheckoutButton client component (`'use client'`)
- ✅ TypeScript strict
- ✅ Accessibility: ARIA labels, semantic HTML, keyboard nav
- ✅ Lighthouse Performance >= 90 (static ağırlıklı)

## Delegation Yönergesi (ZORUNLU)

Bu task **uzun copywriting + UI component + API**. Delegation kritik.

### 1. Next.js 15 current patterns
```
mcp__abs__gemini_search
  "Next.js 15 App Router Stripe Checkout Session API route 2026 best practices. TypeScript. Server Action vs API Route tradeoff."
```

### 2. Türkçe copywriting için `qual_tr`
```
mcp__abs__qual_tr
  "ABS landing hero: 'Claude Pro $20 aboneliğinizle $1000+/ay enterprise seviyesi' temasıyla 3 farklı hero varyantı yaz.
  Ton: dürüst, teknik, marketing dili YOK.
  Her varyant: 1 başlık (20-30 kelime) + 1 alt metin (30-50 kelime) + 2 CTA button metni.
  Halüsinasyon yasak — sadece verdiğim rakamları kullan (75 MCP tool, 6 sağlayıcı, 15dk kurulum, $299 tek seferlik, 14 gün demo)."
```

### 3. React component üretimi için `fullstack fe`
```
mcp__abs__fullstack
  layer: "fe"
  prompt: "Next.js 15 + Tailwind 4 + shadcn/ui ile Hero component.
  Props: title, subtitle, primaryCta{text,href}, secondaryCta{text,href}.
  Dark mode, responsive, accessible.
  (Prompt kısa tut, TPM limit var — önce Hero, sonra Features, sonra Pricing — ayrı çağrılar)"
```

### 4. FAQ içeriği için `ask_qwen32b`
```
mcp__abs__ask_qwen32b
  prompt: "8 FAQ soru-cevap. Her cevap 2-3 cümle, dürüst. [task'taki soru listesini ver]"
```

### 5. CheckoutButton + API route için `qual_code`
```
mcp__abs__qual_code
  prompt: "Next.js 15 App Router + Stripe Checkout Session:
  - app/api/checkout/route.ts (POST)
  - components/CheckoutButton.tsx (client, redirect to stripe url)
  - Env: STRIPE_SECRET_KEY, STRIPE_PRICE_ID_SELF_HOST, STRIPE_PRICE_ID_MAINTENANCE
  - Error handling, TypeScript strict, accessibility"
```

### 6. Final review
```
mcp__abs__code_review
  tier: "standard"
  (tüm Next.js projesini skorla)

mcp__abs__judge_patch
  unified_diff: <git diff>
```

### Hedef Delegation

- En az **%30 delegation** (uzun TR copywriting + UI components)
- MCP çağrıları min **8 kez**

## Adımlar

1. `core/landing/` altına Next.js 15 scaffold (`npx create-next-app@latest` değil — manuel package.json + boş app/ layout)
2. Tailwind + shadcn/ui kur
3. `gemini_search` ile Next.js 15 + Stripe pattern research
4. Hero component (`fullstack fe` delege)
5. Features component (statik içerik, kısa)
6. Pricing component (3 kart, Stripe Checkout entegre)
7. FAQ component (`ask_qwen32b` delege içerik)
8. CheckoutButton + `/api/checkout/route.ts` (`qual_code` delege)
9. Footer
10. SEO metadata + og.png placeholder
11. Test (Vitest) — Hero + CheckoutButton
12. `npm run build` → production build başarılı
13. `npm run dev` → local test
14. `mcp__abs__code_review` + `judge_patch`
15. Summary yaz

## Doğrulama

```bash
cd core/landing

# 1. Install
npm install

# 2. Dev build
npm run build
# Beklenen: error yok, static pages generate

# 3. Dev server
npm run dev
# http://localhost:3000 açılır
# Hero + Features + Pricing + FAQ + Footer tam görünür

# 4. Stripe Checkout (mock)
# "Buy Self-Host" butona tıkla → /api/checkout 200 döner + redirect URL

# 5. Test
npm test
# Beklenen: Hero + CheckoutButton test passed

# 6. Lighthouse (opsiyonel)
# npx lighthouse http://localhost:3000 --only-categories=performance
# Beklenen: >= 90
```

## Tamamlama

1. `git diff` al
2. `mcp__abs__judge_patch` ile skorla
3. `completed/003-landing-summary.md` yaz (Delegation Kullanımı zorunlu)
4. Bu task dosyasını `_agent-tasks/completed/` altına taşı
5. Planlayıcıya "003 tamam" rapor et

### Summary zorunlu alanlar

```markdown
## Ne Yapıldı
[dosya listesi + satır]

## Delegation Kullanımı
- gemini_search: N kez (hangi sorular)
- qual_tr: N kez
- fullstack fe: N kez
- ask_qwen32b: N kez
- qual_code: N kez
- code_review: N kez
- judge_patch: N kez
- Toplam delegation: %X (hedef %30+)

## Screenshot / Demo
- `npm run dev` localhost:3000 screenshot (opsiyonel)
- Lighthouse score

## Eksik / Blocker
- Automatia BCN logo dosyası (varsa path ver)
- Stripe Product ID (henüz oluşturulmadı, env placeholder)
- OG image (placeholder, ileride tasarım)

## Notlar Planlayıcıya
- Gelecek task'lar: Stripe Product ID oluşturma, DNS setup abs.automatiabcn.com, Vercel deploy
```

---

**Tahmini süre:** 3-4 saat (delegation sayesinde)
**Sonraki task:** `004-panel-port.md` — SERVER panel HTML'in ürüne taşınması (auth proxy + multi-config UI)
