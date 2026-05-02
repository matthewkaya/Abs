# Sprint 21 — Faz F font subset + display:swap audit

**Tarih:** 2026-05-02

## Mevcut config (`app/layout.tsx`)

```tsx
const geist = Geist({
  subsets: ["latin", "latin-ext"],   // TR ş/ğ/ı için latin-ext zorunlu
  display: "swap",                    // FOIT önler — fallback'le FCP'yi korur
  variable: "--font-display",
  weight: ["400", "500", "600", "700"],
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin", "latin-ext"],
  display: "swap",
  variable: "--font-mono",
  weight: ["400", "500", "600"],
});
```

## Brief spec ile karşılaştırma

| Kriter | Hedef | Mevcut | Durum |
|--------|-------|--------|-------|
| `subsets` | `["latin", "latin-ext"]` | ✅ aynı | OK |
| `display` | `"swap"` | ✅ swap | OK |
| `weight` prune | sadece kullanılanlar | 4 (Geist) + 3 (Mono) | OK (full 9 weight değil) |
| Self-host | `next/font/google` ile inline | ✅ next/font | OK |
| `preload` | varsayılan true | ✅ next/font default | OK |

## Karar

`Faz F refactor SKIP`. T-R03 sırasında zaten production-grade
font config kuruldu. Subset, display, weight, self-host — hepsi
optimal.

## Aksiyon

Faz G — image optimize'ye geç.
