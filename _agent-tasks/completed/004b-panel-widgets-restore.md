# Task 004b — Panel Widgets Restore (004 Düzeltme)

## Bağlam ve Neden

004 task'ında panel port edilirken **7 widget kaldırıldı**. Kullanıcı kararı: **Feature parity zorunlu — SERVER widget'ları çıkarılamaz**. `docs/design-decisions.md` § 5 "Feature Parity: Tam Set + **Fazlası**" kararına aykırı.

Bu task o kaldırılan 7 widget'ı **geri getirir**. Adaptasyon kuralları aynı (hardcoded path/IP sil, tenant-aware, branding), ama widget'lar **korunmalı**.

## Geri Getirilecek 7 Widget

004 summary'de kaldırılan liste:

1. **Symbol Explorer** — RAG gelişmiş sembol arama + filtreler
2. **Quota Radar** — 6 provider kota görselleştirme (daire grafiği)
3. **Anchor Nav** — sayfa içi hızlı erişim menüsü (section jump)
4. **Notification Bell** — sistem bildirimleri merkezi
5. **Theme Toggle** — dark/light tema geçişi
6. **Disagreement Panel** — multi-model consensus visualization
7. **Vital Signs Strip** — cosmos sağ kolon özet metrik şeridi

## Kaynaklar (SERVER'dan Read-only)

SERVER panel'de bu widget'ları **tek tek** bul:

- `/Users/eneseserkan/Main/Automatia BCN/SERVER/automatiabcn_panel_v2.html` (7550 satır)

Her widget'ın yaklaşık satır aralıkları (grep ile doğrula):

```bash
# İşçi Claude bu grep komutlarını çalıştırabilir
grep -n "symbol-explorer\|sym-explorer" [file]
grep -n "quota-radar\|renderQuotaRadar" [file]
grep -n "anchor-nav\|sec-jump" [file]
grep -n "notif-bell\|notification" [file]
grep -n "theme-toggle\|data-theme" [file]
grep -n "disagree-panel\|disagreement-matrix" [file]
grep -n "vital-signs\|cosmos-strip" [file]
```

## Beklenen Çıktı

### 1. Panel HTML güncelleme (`core/backend/app/static/panel/index.html`)

Her widget için:
- [ ] HTML section + widget markup
- [ ] CSS (panel'in mevcut style bloklarına entegre)
- [ ] JS (widget render fonksiyonu + polling/SSE hook)
- [ ] ID'ler SERVER ile birebir aynı (test parity için)

### 2. Backend endpoint'ler (gerekliyse)

Bazı widget'lar backend endpoint gerektirir:
- `/api/symbol-graph/neighbors?name=X` (Symbol Explorer)
- `/api/quota-status` (Quota Radar)
- `/api/disagreement/latest` (Disagreement Panel)
- Notification Bell, Theme Toggle, Anchor Nav, Vital Signs → frontend-only

- [ ] `app/api/symbol_graph.py` — stub endpoint (veriyi 009'dan alır, şimdilik placeholder)
- [ ] `app/api/quota.py` — stub endpoint (006'dan provider cascade health verisi)
- [ ] `app/api/disagreement.py` — stub (ask_disagree 008'de port edilecek)

**Not:** Stub endpoint'ler placeholder payload döndürmeli (panel JS çalışabilsin). Gerçek veri sonraki task'larda (006, 008, 009) bağlanacak.

### 3. Adaptasyon (004'teki gibi)

Her widget'ı port ederken:
- Hardcoded path/IP sil
- 3-cihaz referansları temizle
- `localhost:8889`, `100.100.110.44` vb. → relative URL (aynı origin)
- Widget ID + CSS class isimleri SERVER ile **aynı** kalsın

### 4. Test

- [ ] `tests/test_panel_widgets.py`:
  - `test_panel_has_all_widgets()` — 15 widget (8 mevcut + 7 restore) ID'leri HTML'de var
  - `test_widget_apis_reachable()` — symbol_graph, quota, disagreement stub endpoint'leri 200 dönüyor
- [ ] Playwright live render güncelleme — 15 widget görünüyor ekran görüntüsü (`panel-home-full.png`)

## Kısıtlar

- ❌ SERVER'a Write/Edit
- ❌ Widget çıkarma / basitleştirme (geri getir, aynı kalsın)
- ❌ Widget davranışını değiştirme (aynı görünüm, aynı işlev)
- ✅ Stub endpoint'ler placeholder payload döner (gerçek veri sonra)
- ✅ Widget ID + CSS class parity (test guard için)

## Delegation Yönergesi

### 1. SERVER'da her widget'ı bul

```
Read /Users/eneseserkan/Main/Automatia BCN/SERVER/automatiabcn_panel_v2.html offset=N limit=200
# Her widget için ayrı chunk read (grep ile satır bul)
```

### 2. Widget adaptasyon için `qual_code` (TEK widget her çağrıda — TPM)

```
mcp__abs__qual_code
  prompt: "Bu HTML+JS widget'ı ABS ürününe port et:
  [SERVER kod, ~150 satır]
  Değişiklikler:
  - URL'ler relative (/api/...)
  - Hardcoded host yok
  - ID + class aynı kalsın (test parity)
  Davranışı bozma."
```

### 3. Stub endpoint'ler için `ask_kimi` (basit kod)

```
mcp__abs__ask_kimi
  "FastAPI stub endpoint'ler:
  - GET /api/symbol-graph/neighbors → {status: 'empty', neighbors: []}
  - GET /api/quota-status → {status: 'empty', providers: {}}
  - GET /api/disagreement/latest → {status: 'empty'}
  Auth required. Placeholder, gerçek implementation sonraki task'larda."
```

### 4. Playwright re-render

```
mcp__playwright__browser_navigate http://localhost/panel
mcp__playwright__browser_take_screenshot → panel-home-full.png
# 15 widget görünür olmalı
```

### 5. Final skor

```
mcp__abs__code_review tier="quick"
mcp__abs__judge_patch
```

### Hedef Delegation

- Min **%25 delegation** (widget restore ağırlıklı adaptasyon iş)
- MCP çağrı min **6 kez**

## Doğrulama

```bash
cd core/backend
.venv/bin/pytest tests/ -q
# Beklenen: önceki 24 + yeni 2 test = 26 passed (veya 39 eğer 005 de bitmişse)

cd ../../infra
docker compose restart backend

# Panel'de 15 widget kontrol
curl -k -b cookies.txt https://abs.local/panel | \
  grep -E "cosmos-hybrid|workflow-card|judge-body|cohere-alert-banner|\
spark-deleg|spark-cache|cs-budget|sym-explorer|quota-radar-grid|\
disagree-body|notif-bell|theme-toggle|cosmos-strip"
# 15 eşleşme beklenir
```

## Tamamlama

1. `judge_patch` skor
2. `completed/004b-panel-widgets-restore-summary.md`:
   ```markdown
   ## Ne Yapıldı
   - Geri getirilen 7 widget (+ 8 mevcut = 15 toplam)
   - Stub endpoint'ler (3 tane, placeholder)
   - Test + Playwright screenshot (panel-home-full.png)

   ## Widget Port Satır Sayıları
   - Symbol Explorer: N satır
   - Quota Radar: N satır
   - ...

   ## Delegation Kullanımı
   ...

   ## Stub Endpoint'ler (gerçek veri sonraki task'larda)
   - /api/symbol-graph → 008 (RAG port) bağlayacak
   - /api/quota-status → 006 (provider cascade) besleyecek
   - /api/disagreement → 008 (ask_disagree) bağlayacak
   ```
3. Task'ı `completed/`'e taşı
4. "004b tamam" rapor

---

**Tahmini süre:** 2-3 saat
**Sonraki task:** `005-orchestrator-mcp-shell.md` (zaten yazıldı, 004b'den sonra başlar)
