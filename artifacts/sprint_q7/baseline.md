# Q7 Baseline — 2026-04-30

## Cumulative chain (Q5 runner)
- sprint_hotfix_cj: 17/17 PASS
- sprint_20_impl: 15/15 PASS
- sprint_q1_quality: 30/30 PASS
- sprint_q2_master: 8/8 PASS
- sprint_q3: 8/8 PASS
- sprint_q4: 8/8 PASS
- **Chain total: 86/86 PASS, 0 FAIL**

## Q6 standalone
- 13/13 PASS

## Cumulative pre-Q7
**99/99 PASS** (chain 86 + Q6 13)

## Brief drift claim
Brief said "93/99 baseline 6 FAIL admin@demo-acme.local 401". **Refuted** — chain runner's per-sprint `seed_admin` already injects credentials before each repro. Phase D will still ship a standalone credential reset script as defense-in-depth for individual sprint runs outside the chain.

## Pre-approved decisions (worker brief)
1. NEO4J_PASSWORD: default `AbsNeo2026!` (vault Q8)
2. Plugin images: stub busybox + healthcheck script
3. Cosign: dev-only skip mode (prod Q8)
4. UI stack: shadcn/ui + Tremor + Framer Motion + TanStack Query — APPROVED
5. Cosmos: frontend remove, ops panel `automatiabcn_panel_v2.html` PRESERVED

## Q7 target
- Phase A: 5/5 endpoint + Neo4j live + NL query e2e
- Phase B: 5 plugin install + 7/7 edge case + 0 cross-leak
- Phase C: 7 panel pages premium + Lighthouse ≥ 90 + cosmos removed
- Phase D: 99+/99 cumulative (regression target)
- Phase E: 0 new CRIT/HIGH

**Final cumulative target:** 107/107 (99 pre + 8 Q7)
