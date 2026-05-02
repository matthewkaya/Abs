# Sprint 21 — Faz E Lucide tree-shake audit

**Tarih:** 2026-05-02

## Bulgu

`lucide-react@^0.468.0` ESM tree-shaking modern Next.js
webpack/SWC altında **zaten doğru** çalışıyor.

`grep -c "lucide" /tmp/q10-standalone/.next/static/chunks/*.js`:

| Chunk | Boyut | Lucide refs |
|-------|------:|------------:|
| 2058 | 24K | 1 |
| 5612 | 20K | 1 |
| 9166 | 8K | 1 |
| 9612 | 12K | 1 |
| **toplam** | **64K** | route'lara dağıtılmış |

Diğer ~50 chunk'ta lucide referansı yok — webpack `usedExports +
sideEffects: false` ile sadece kullanılan icon JSX'lerini bundling.

## Karar

`Faz E refactor SKIP`. Per-icon import (`lucide-react/dist/esm/icons/<name>`)
şu anda **net win sağlamaz** çünkü:
1. Bundle zaten 64K — ekstra optimization marjı dar
2. Per-icon import IDE auto-import'unu bozar (dev experience)
3. Refactor ~30+ dosya × 5+ icon = sürtünme

Eski Lucide (<0.300) full-lib import yapıyordu (~500K). Bu codebase
0.468 sürümünde → modern ESM exports map.

## Aksiyon

Faz F — font subset audit'e geç.
