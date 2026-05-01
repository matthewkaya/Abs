# Q10 Round 15 — Layer L7 visual regression baseline (live)

**Tarih:** 2026-05-01
**Branch:** `feat/sprint-q10-quality-loop`
**Commit:** `c24b450`
**Mode:** Prod build (port 3458), not dev — Round 12'de keşfedilen
dev-mode HMR thrash policy.

---

## Çıkarım

Spec ship etmek round'u ilerletmiyor (brief'te açık emir). Round 9'da
shipped `q10-l7-visual-regression.spec.ts` bu round'da **canlı çalıştı**.
İlk attempt dev :3000 üzerinde 5/10 fail (auth cookie sorunu + HMR
thrash). Prod build hand-off'a geçildi.

---

## Q10-L7-001 — Production build was broken (HIGH → fix)

`npm run build` ESLint failure:

```
./app/panel/meetings/[id]/page.tsx
80:7  Error: Do not use an `<a>` element to navigate to `/panel/meetings/`.
       Use `<Link />` from `next/link` instead.
       @next/next/no-html-link-for-pages
```

**Severity:** HIGH — production deploy artifact üretilemiyor.

**Kök neden:** Phase Q9 meetings detail page bare `<a>` ile geri-link
yapıyordu. Next 15 strict-mode için `no-html-link-for-pages` rule
**build-fail** kategorisinde (warning değil).

**Fix:** `import Link from "next/link"` + `<a>` → `<Link>`.

Post-fix `npm run build`: 30+ route emit, 0 hata. `/panel`, `/panel/chat`,
`/admin/*` standalone bundle'da mevcut.

---

## Visual baseline run

### Setup

- prod server: `npx next start -p 3458` (warning: standalone-config
  uyarısı var, ama functional)
- 10 surface, theme=dark default
- 2% anti-alias tolerance, animations=disabled, fullPage

### Run 1 (--update-snapshots)

```
[10/10] q10-l7 users screenshot
... 10 PNG generated
10 passed (14.0s)
```

PNG'ler `__tests__/playwright/q10-l7-visual-regression.spec.ts-snapshots/`:

| Surface | PNG |
|---------|-----|
| panel | panel-chromium-desktop-darwin.png |
| chat | chat-chromium-desktop-darwin.png |
| tools | tools-chromium-desktop-darwin.png |
| providers | providers-chromium-desktop-darwin.png |
| pipelines | pipelines-chromium-desktop-darwin.png |
| rag | rag-chromium-desktop-darwin.png |
| marketplace | marketplace-chromium-desktop-darwin.png |
| quota | quota-chromium-desktop-darwin.png |
| settings | settings-chromium-desktop-darwin.png |
| users | users-chromium-desktop-darwin.png |

### Run 2 (diff against baseline)

```
[10/10] q10-l7 users screenshot
10 passed (15.9s)
```

0 px-delta beyond 2% tolerance. Baseline yerleşik.

---

## Auth flow keşif (debug spec)

İlk dev-mode failure'ı incelemek için geçici `debug_auth.spec.ts`
yazıldı + silindi. Bulgular:

- Cookie domain: `localhost`, sameSite: `Strict`, httpOnly: true
- `page.request.post('/auth/login')` cookie'yi browser context'e
  doğru yazıyor (4 cookie field PASS)
- Stale prod server (önceki Q10-L7-001 öncesi build) `/panel` 404
  veriyordu → restart sonrası 200

Bu bulgular `q8-customer-journey.spec.ts`'in mevcut `loginIfNeeded`
pattern'ini doğruladı; spec'te değişiklik gerekmedi.

---

## L7 layer durumu

| Audit hedefi | Round 15 sonu |
|--------------|---------------|
| spec ship | ✅ (Round 9) |
| baseline run (live, prod build) | ✅ 10/10 PASS |
| diff run (regression check) | ✅ 10/10 PASS |
| Q10-L7-001 prod build break | ✅ fix |

L7 3-round-clean sayacı: **1/3 → 2/3**.

---

## Atomic commit

`c24b450` — fix(q10/L7): Round 15 — Q10-L7-001 prod build break + visual baseline

Files: 1 src fix + 10 baseline PNGs + scheduled_tasks.lock untouched.

---

## Sonraki round

**Round 16 = L5 Lighthouse headless run.**

`lighthouserc-panel.json` ile prod build :3458 üzerinde 4 panel
sayfa (panel, chat, tools, quota) ölç. Hedef ≥90 (perf, a11y, BP, SEO).
Dipsiz olanları fix et.

---

## Yan kazanım — Q10-L7-001 fix prod-blocking severity

Bu Q10-L7 round'u sayesinde **production deploy yetenekli olmayan** bir
durumdan çıkıldı. Sprint 17'de "Lighthouse 100/100/100/100" claim'i
vardı (CLAUDE.md), ama o pre-Q9 baseline'dı. Q9 phase eklemelerinde
beraberinde gelen bare `<a>` regression bu round'da yakalandı + fix.

---

**Round 15 status:** ✅ ship — Q10-L7-001 fix + 10 baseline PNG +
2-round 0 regression. L7 sayacı 1/3 → 2/3.
