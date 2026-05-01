# Phase A — Pricing strip (PASS)

Customer-facing files swept clean:
- `core/landing/app/page.tsx` hero/CTA pricing-free (user manual edit)
- `core/landing/app/showcase/page.tsx` `Cascade savings $1,142` → `Cascade routed 3,420`
- `core/landing/app/refund/page.tsx` redirects to `/#contact`
- `core/landing/app/pricing/page.tsx` redirects to `/#contact`
- `core/landing/app/layout.tsx` meta — pricing-free
- `core/landing/components/Pricing.tsx` no-op stub
- `core/landing/components/PricingPage.tsx` rewritten as Pilot/PoC contact CTA

Sweep before: 81 hits across landing+backend+docs (mostly internal docs).
Sweep after (customer-facing only): 0 user-visible pricing strings (verified
via `curl http://localhost:3000/{,/showcase,/pricing}` — no `$NNN` user-visible
strings; React hydration markers like `$3..$7` are internal).

Live verification:
- `/showcase` → no `$1,142` after Next.js rebuild (verified via grep on body)
- `/pricing` → 307 to `/#contact` (Q5 user manual edit)
- `/refund`  → 307 to `/#contact` (Q5 user manual edit)

PASS — no customer-facing pricing artefacts remain.
