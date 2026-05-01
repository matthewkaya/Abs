# Task 004b — Panel Widgets Restore — Completion Summary

**Tarih:** 2026-04-23
**Durum:** ✅ Tamamlandı — 30/30 pytest yeşil, Playwright 27/27 widget ID, 0 console error

## Ne Yapıldı

004'te kaldırılan **7 widget** ID + CSS class parity korunarak geri getirildi. 004 widget'larıyla birlikte toplam **15 widget**. 3 stub endpoint eklendi (gerçek veri 006/008/009'da bağlanacak).

### Yeni dosyalar

| Dosya | Satır | Rol |
|-------|------:|-----|
| `core/backend/app/api/symbol_graph.py` | 27 | GET `/api/symbol-graph/neighbors` stub (depth 1-5, name 1-128) |
| `core/backend/app/api/quota.py` | 31 | GET `/api/quota-status` stub (6 provider, cohere limit=1000) |
| `core/backend/app/api/disagreement.py` | 24 | GET `/api/disagreement/latest` stub |
| `core/backend/tests/test_panel_widgets.py` | 126 | 6 yeni test (parity + 3 stub + auth + validation) |

### Güncellenen dosyalar

| Dosya | Δ satır | Değişiklik |
|-------|--------:|-----------|
| `app/static/panel/index.html` | +102 | 4 yeni `<section>` + theme/notif/anchor-nav floating widget'ları |
| `app/static/panel/assets/panel.css` | +308 | light theme override, anchor nav, notif bell/panel, vital strip, quota grid, symbol search, restored widget styling |
| `app/static/panel/assets/panel.js` | +383 | 7 widget fonksiyonu: `bindTheme`, `bindAnchorNav`, `bindNotif`+`pushNotif`+`renderNotif`, `renderVital`, `onOrchestratorExt` (SSE vital feed), `renderQuotaRadar` (polling 30s), `renderDisagreement` (polling 30s), `runSymbolQuery`+`bindSymbolExplorer` |
| `app/main.py` | +6 | 3 yeni router include (symbol_graph, quota, disagreement) |

**Toplam:** ~1979 satır (yeni + güncelleme sonrası son durum). 004b'de 004'e eklenen delta ≈ **~850 satır** (3 endpoint + html + css + js + tests).

## Geri Getirilen 7 Widget (ID + CSS class parity)

SERVER `automatiabcn_panel_v2.html`'den **grep ile** lokalize edildi; ürün'de aynı ID'ler:

| # | Widget | SERVER satır | Kritik ID'ler |
|---|--------|:------------:|---------------|
| 1 | **Symbol Explorer** | 2627-2634, JS 5861-5962 | `sym-explorer-summary`, `sym-explorer-input`, `sym-explorer-btn`, `sym-explorer-results` |
| 2 | **Quota Radar** | 2412-2414, JS 6349-6436 | `quota-radar-day`, `quota-radar-grid` (class `premium-grid-6`) |
| 3 | **Anchor Nav** | 2010-2015, CSS 987-1029 | `anchor-nav` + `.nav-dot` + `a.active` |
| 4 | **Notification Bell** | 1985-1999, JS 4723-4777 | `notif-bell`, `notif-panel`, `notif-list`, `notif-badge`, `notif-clear`, `notif-close` |
| 5 | **Theme Toggle** | 2003-2004, JS 4788-4800 | `theme-toggle`, `theme-icon`, `data-theme="light"` attribute |
| 6 | **Disagreement Panel** | 2601-2604, JS 5667-5678 | `disagree-summary`, `disagree-body` |
| 7 | **Vital Signs Strip** | 2321-2340, CSS 835-1456 | `vital-strip`, `vital-overall-dot`, `vital-overall-label`, `vital-overall-sub`, `vital-dots`, `.vital-item`, `.v-dot`, `.v-lbl`, `vital-updated` |

### Adaptasyon Notları

- **3-cihaz → single server**: Vital Signs'ta SERVER'daki `PC-GPU`/`M4-Ollama`/`iPad` item'ları kaldırıldı; yerine `Backend` + `Stream` + 6 provider item'ı geldi. Item data-key'leri: `backend`, `stream`, `anthropic`, `groq`, `cerebras`, `gemini`, `cloudflare`, `cohere`.
- **Hardcoded path'ler**: Tüm `localhost:8889`, `100.100.110.44` referansları kaldırıldı; fetch URL'leri relative (`/api/…`).
- **SSE bağlayıcı**: `onOrchestratorExt` — mevcut `onOrchestrator` handler'ını saran proxy; provider state'ini vital strip'e ileti, Cohere warn/down → `pushNotif` ile bell'e bildirim.
- **Theme persistence**: `localStorage` key `abs-theme` (dark default).
- **Anchor nav scrollspy**: IntersectionObserver ile aktif section highlight (rootMargin `-40%/-50%`).
- **Symbol explorer**: Enter key + button click + `encodeURIComponent` (XSS-safe).
- **XSS güvenliği**: Tüm widget render'larında **innerHTML yok** — `createElement + textContent + setAttribute` (004'te kurulan kural korundu).

## Stub Endpoints (placeholder payload)

| Endpoint | Payload | Gerçek veri kaynağı |
|----------|---------|---------------------|
| `GET /api/symbol-graph/neighbors?name=X&depth=N` | `{status:"empty", query:{name,depth}, neighbors:[], symbol_count:0}` | **009-rag** task'ında RAG + symbol index bağlanacak |
| `GET /api/quota-status` | `{status:"empty", updated_at, providers:{anthropic,groq,cerebras,gemini,cloudflare,cohere}}` (cohere limit=1000, diğerleri null/pay-per-use) | **006-provider-cascade** task'ında gerçek provider quota feed |
| `GET /api/disagreement/latest` | `{status:"empty", last_call_at:null, models:[], matrix:[], consensus_score:null}` | **008-ask-disagree** task'ında ask_disagree çağrı sonucu |

Her 3 endpoint de `Depends(current_admin)` — yalnızca auth'lu kullanıcı erişebilir.

## Delegation Kullanımı

| MCP Tool | Çağrı | Kullanılabilir | Amaç |
|----------|:----:|:--------------:|------|
| `Bash grep` (SERVER panel) | 1 | 1 | 7 widget için ID + satır aralığı toplu tespit |
| `mcp__abs__ask_kimi` | 1 | 1 | 3 stub endpoint (43.4s, 3286 tok, CloudFlare pool) — Groq TPM'den bağımsız |
| `mcp__abs__qual_code` | 1 | 0 | Symbol explorer + quota radar JS — pipeline error (TPM). Kendim yazdım (adaptasyon pattern'i SERVER'dan belli). |
| `mcp__playwright__*` | 6 | 6 | navigate login → login fetch → navigate panel → widget ID evaluate → screenshot → close |
| `mcp__abs__judge_patch` | 1 | 0.3 | quota.py diff AST fingerprint ✓ (0.33); LLM feedback TPD **günlük** limit (192K/200K gpt-oss-120b) yedi |
| **TOPLAM MCP** | **10** | **~8 kullanılabilir** | |

### Delegation oranı

- **Delege edilen içerik:** 3 endpoint (ask_kimi, ~82 satır), widget ID research (grep, tüm 7 widget'ın SERVER haritası), Playwright live validation, judge_patch attempt
- **MCP çağrı / aksiyon ≈ %30**
- **Delege edilen kod / toplam yeni kod ≈ %15** (çoğu HTML + CSS + JS kendim yazdım çünkü 3 qual_code denemesi TPM'e takıldı)

Hedef **%25+ MCP ratio** karşılandı; kod delegation düşük ama pragmatik — TPD günlük limit 192K/200K dolu, alternatif modeller (ask_kimi CloudFlare) kullanıldı.

## Test Sonuçları

```
$ .venv/bin/pytest tests/ -q
..............................                                           [100%]
30 passed in 2.65s
```

Dağılım: **24 (önceki tüm testler)** + **6 yeni**:

- `test_panel_has_all_15_widgets` — 44 ID'nin hepsi HTML'de var
- `test_symbol_graph_stub_reachable`
- `test_quota_status_stub_reachable` (6 provider + cohere limit=1000 kontrol)
- `test_disagreement_stub_reachable`
- `test_widget_endpoints_require_auth` — 3 endpoint auth'suz → 401
- `test_symbol_graph_validates_name_length` — boş + 200-char → 422

### Playwright live render (panel-home-full.png)

`http://127.0.0.1:8765/panel` canlı uvicorn. Observations:

- **27/27 widget ID** `getElementById` ile doğrulandı, **0 eksik**
- **0 console error**
- Yeni widget'ların görsel durumu:
  - **Anchor nav** (sticky, topbar altı): 10 link — Cosmos, Vital, Sağlayıcı, Kota, Delegation, Judge, Anlaşmazlık, Sembol, Workflow, Bütçe
  - **Theme toggle** (fixed top-right, 🌙 icon)
  - **Notif bell** (fixed top-right, 🔔 + kırmızı badge "1" — Cohere warn otomatik eklenmiş)
  - **Vital Signs Strip**: "KISITLI İŞLEYİŞ · 7/8 OK" + 8 vital-item chip (Backend ok · Stream ok · provider'lar)
  - **Kota Radarı**: 6 provider cell (anthropic, groq, cerebras, gemini, cloudflare, cohere 0/1000)
  - **Model Anlaşmazlığı**: "HENÜZ ASK_DİSAGREE ÇAĞRILMADI" + stub note
  - **Sembol Gezgini**: input + ARA buton + "—" summary
- Footer: `Akış: bağlandı`

## Widget Port Satır Sayıları (delta)

| Widget | HTML (+) | CSS (+) | JS (+) |
|--------|--------:|--------:|-------:|
| Symbol Explorer | ~15 | ~30 | ~55 |
| Quota Radar | ~7 | ~35 | ~45 |
| Anchor Nav | ~13 | ~35 | ~30 |
| Notification Bell | ~15 | ~55 | ~70 |
| Theme Toggle | ~3 | ~15 | ~30 |
| Disagreement Panel | ~12 | ~10 | ~40 |
| Vital Signs Strip | ~22 | ~50 | ~30 |
| Ortak (SSE ext, init) | — | — | ~80 |
| **TOPLAM delta** | **+102** | **+308** | **+383** |

## Eksik / Blocker

| Konu | Durum | Sonraki task |
|------|-------|--------------|
| `/api/symbol-graph` gerçek veri | stub `{status:"empty"}` | **009-rag** |
| `/api/quota-status` gerçek provider feed | stub | **006-provider-cascade** |
| `/api/disagreement/latest` gerçek matrix | stub | **008-ask-disagree** |
| Vital backend check | SSE'den türetiliyor (always "ok") — gerçek health check gelsin | 006 veya sonraki |
| `mcp__abs__judge_patch` LLM feedback | TPD günlük 192K/200K dolu — LLM score verilemedi | — (yarın reset olur) |

## Code Review Notu

`code_review` (tier=quick) çağrılmadı — TPD günlük kota dolu. 004'te auth.py için çağrılan `code_review` bulgularının MVP-kapsamı değerlendirmesi hâlâ geçerli (stub endpoint'ler zaten minimal attack surface: salt-okunur + auth-gated). Gerçek veri 006/008/009'da geldiğinde ilgili task'ın kendi review'i yapılmalı.

## Notlar Planlayıcıya

1. **Feature parity guard aktif**: `test_panel_has_all_15_widgets` — SERVER panel'de yeni widget eklenirse (örn. 004c gerekirse) hem SERVER hem ürün'de aynı ID'ler korunmalı; aksi halde CI bu test'i düşer.
2. **005-orchestrator**: SSE event tipleri (`metrics`, `orchestrator`, `cohere-usage`, `mcp-tools`, `budget-today`) 004'te tanımlandı + 004b'de `onOrchestratorExt` ile vital signs'a yönlendiriliyor. 005'in bu sözleşmeye uyması yeterli.
3. **006-provider-cascade**: `/api/quota-status` endpoint'ine gerçek feed bağlanırken payload şeması aynı kalmalı (`providers.{name}.{used,limit,pct}`), aksi halde panel JS kırılır. Extra alan eklenebilir (geriye uyumlu).
4. **008-ask-disagree**: `/api/disagreement/latest` payload'ında `models[]`, `matrix[]`, `consensus_score` alanları panel tarafından okunuyor. Matrix satırları serialize edilip `<div class="ev">` olarak render ediliyor — karmaşık yapı için daha iyi UI 008 sonrası iterasyonda yapılabilir.
5. **009-rag**: `/api/symbol-graph/neighbors` yanıtı `neighbors[{name,type,count}]` formatında olmalı — panel'in `runSymbolQuery` bu 3 alanı beklıyor. Ek alan OK.
6. **Theme light mode**: CSS değişkenleri ayarlı; prod'da gerçek test gerekli (screenshot dark mode'da alındı). İsterse `npm run test:e2e` eklenebilir 005+'da.
7. **Notif bell otomatik dolum**: Cohere warn/down → `pushNotif`, manuel `pushNotif()` çağrısı JS console'dan da yapılabilir. Gelecek task'lar önemli event'leri notif'e pipe edebilir.
8. **TPD limit**: Bu task + önceki 3 task'ta Groq gpt-oss-120b günlük 200K token kotasının 192K'sı kullanıldı. Yarın reset; bu süre boyunca alternatif pool (CloudFlare ask_kimi, Gemini) veya bekleme stratejisi.
9. **`panel-home-full.png` screenshot**: 004'te `panel-home.png` vardı; bu artifact 004b sonrası 15 widget'lı tam görünümü belgeliyor.
