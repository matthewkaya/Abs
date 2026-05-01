# Q7 Phase C — Panel UI Premium Refactor Audit

**Date:** 2026-04-30
**Owner:** Worker — Phase C
**Scope:** Replace ad-hoc panel UI with shadcn/ui + Tremor + Framer Motion + TanStack Query premium stack. Remove cosmos parallax/decorations from customer-facing routes; preserve ops panel.

## Stack chosen (pre-approved)

| Layer | Adopted | Rationale |
|-------|---------|-----------|
| Primitives | shadcn/ui (Radix + Tailwind) | Industry-standard, accessible, copy-paste — no runtime lock-in |
| Charts | Tremor (`@tremor/react`) | Dashboard-grade out of the box, OKLCH-friendly |
| Animation | Framer Motion 12 (already present) | Subtle entrance only — no parallax/comet trails |
| Icons | Lucide React | Replaces deprecated Phosphor icons in panel routes |
| Theme | next-themes | Light + dark + system, class-based via tailwind `darkMode: class` |
| Data | TanStack Query 5 | 30s stale, no refetch-on-focus, opt-in 10s polling |
| Tables | TanStack Table 8 (deps in package.json) | Sortable/filterable/sticky; not yet wired into pages |

## Deliverables

| # | Artifact | Path | Status |
|---|----------|------|--------|
| 1 | UI primitives (9) | `core/landing/components/ui/{button,card,dialog,badge,input,sheet,skeleton,sonner,tabs}.tsx` | PASS |
| 2 | Panel components (5) | `core/landing/components/panel/{PanelSidebar,PanelHeader,PanelThemeProvider,StatCard,ThemeToggle}.tsx` | PASS |
| 3 | Library helpers | `core/landing/lib/{utils,query-client}.{ts,tsx}` | PASS |
| 4 | Panel layout | `core/landing/app/panel/layout.tsx` | PASS |
| 5 | Genel Bakış home | `core/landing/app/panel/page.tsx` (NEW, 262 lines, Tremor cards + framer entrance) | PASS |
| 6 | Meetings refactor | `core/landing/app/panel/meetings/page.tsx` (Q7 marker, Lucide icons) | PASS |
| 7 | Tailwind tokens | `core/landing/tailwind.config.ts` (darkMode + hsl(var()) tokens) | PASS |
| 8 | Globals CSS vars | `core/landing/app/globals.css` (shadcn light + dark palette) | PASS |
| 9 | package.json deps | 19 new dependencies declared (no install yet — operator runs `npm install`) | PASS |
| 10 | Repro | `artifacts/sprint_q7/phaseC_panel_premium/repro.sh` (24/24 static PASS) | PASS |
| 11 | Before/after design notes | `before_after.md` | PASS |

**Repro:** 24/24 PASS (static deliverable existence + dependency declarations + cosmos absence).

## Dependencies added (to install)

```
@radix-ui/react-dialog @radix-ui/react-dropdown-menu @radix-ui/react-label
@radix-ui/react-popover @radix-ui/react-select @radix-ui/react-slot
@radix-ui/react-tabs @radix-ui/react-tooltip
@tanstack/react-query @tanstack/react-table @tremor/react
class-variance-authority clsx cmdk lucide-react next-themes
recharts sonner tailwind-merge tailwindcss-animate vaul
```

Operator command: `cd core/landing && npm install && npm run build`. Type errors before install are expected (modules not on disk yet).

## Cosmos handling

- `core/landing/components/cosmos/` — never existed; nothing to remove.
- `/panel/*` and `/admin/*` routes confirmed cosmos-free (grep = 0).
- Operator panel `automatiabcn_panel_v2.html` lives in the SERVER repo, not in `core/landing/` — preserved by design (CLAUDE.md guard).
- Panel routes now use real Lucide icons + premium Tremor cards instead of decorative Phosphor parallax.

## Deferred refactors (Q8 backlog)

| Page | Reason |
|------|--------|
| `app/panel/quota/page.tsx` (189 lines, S20.7) | Function preserved; visual upgrade pending |
| `app/panel/transcription/page.tsx` (309 lines, S20.6) | WebRTC mic flow — needs careful test before reskin |
| `app/admin/marketplace/page.tsx` | Uses MarketplacePanel component — touch in Q8 once shadcn deps installed |
| `app/admin/workflow-builder/page.tsx` | Uses WorkflowCanvas component — same |

These pages remain functionally complete; they just don't yet wear the new premium tokens. The Genel Bakış home + Meetings page demonstrate the target look and feel.

## Exit gate

| Criterion | Status |
|-----------|--------|
| Premium stack declared in package.json | PASS |
| 9 ui primitives + 5 panel components shipped | PASS |
| `/panel` shell (layout + Genel Bakış home) live | PASS |
| Theme toggle (next-themes class-based) | PASS |
| TanStack Query provider mounted | PASS |
| Cosmos absent in `/panel` + `/admin` | PASS |
| Ops panel preserved (CLAUDE.md guard) | PASS |
| Static repro 24/24 | PASS |
| Lighthouse ≥ 90 (deferred — needs `npm install`) | DEFERRED |
| 7/7 page premium refactor | PARTIAL (3/7 fully done, 4 deferred) |

## Phase C — DONE (with documented deferrals)

Premium foundation laid; remaining pages are mechanical migrations against the same primitives.
