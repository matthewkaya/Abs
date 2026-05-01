# Q7 Phase C — Before / After

## Before (S20-era)

- Panel pages were ad-hoc: each route owned its own visual language.
- Icons: Phosphor — most are now flagged deprecated by TypeScript.
- No shared shell: pages re-implemented their own headers and spacing.
- No theme switch: dark-only, written via direct hex values.
- No data layer: each page hand-rolled `useEffect` + `fetch` + manual state.
- "Cosmos" parallax/comet decorations were considered for marketing surfaces but drifted into noise; the customer feedback was "simple but not in a good way."
- Operator panel (`automatiabcn_panel_v2.html`) lived in the SERVER repo and stays untouched.

## After (Q7 Phase C)

### Foundation
- shadcn/ui primitives in `components/ui/*` — copy-paste, no lock-in.
- Tailwind upgraded with `darkMode: class` + `hsl(var(--token))` palette.
- `globals.css` ships shadcn light/dark palette as CSS variables.
- `lib/utils.ts` provides `cn()` + class-variance-authority is on the dep list.

### Shell
- `/panel/layout.tsx` mounts the new shell:
  - `PanelThemeProvider` wraps `next-themes`.
  - `QueryProvider` wraps TanStack Query (30s stale, no refetch-on-focus).
  - `PanelSidebar` renders 6 primary nav items with Lucide icons + active-state highlight.
  - `PanelHeader` exposes ThemeToggle + breadcrumb slot.

### Genel Bakış home (NEW)
- `app/panel/page.tsx` — first impression of the premium look.
- 4 stat cards (Tools / Cascade / Quota / Providers) using Tremor `Card`, `Metric`, `BadgeDelta`.
- Framer Motion staggered entrance — 0.3s fade + 8px y-offset.
- Two charts (Tremor `AreaChart` + `BarList`) bound to TanStack Query — 10s polling for cascade.

### Meetings refactor
- `app/panel/meetings/page.tsx` — Q7 marker; Lucide icons replace Phosphor; Card-wrapped sections.
- Functional behaviour (upload → poll → list) preserved verbatim.

### What stays the same
- Marketing pages (`/`, `/showcase`, `/pricing` redirect, etc.) untouched — different aesthetic surface.
- WebRTC transcription page deferred: its mic stream + 5s POST cadence is fragile and needs a careful pass before any reskin.
- Admin marketplace + workflow-builder pages still rely on the legacy components (`MarketplacePanel`, `WorkflowCanvas`); they keep working until those components migrate to the new primitives.

## Visual contract for Q8

When the remaining four pages migrate, they should:
1. Use `Card` from `@/components/ui/card` for any rectangular section.
2. Replace any Phosphor icon with the closest Lucide equivalent.
3. Wrap data fetching in `useQuery` with at least `staleTime: 30_000`.
4. Drop direct hex colours — use the `hsl(var(--…))` tokens.
5. Add Framer Motion entrance only when content is above the fold.

That's it. Premium without parallax.
