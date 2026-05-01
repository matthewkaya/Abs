# Task 033 — Demo Readiness + UX Polish (Toplantı için kritik)

**Status:** READY (Worker autonomous mode — 030-032 chain'inden sonra devam)
**Tahmini süre:** 5-6 saat
**Bağımlı task'lar:** 010-032 hepsi (özellikle 018 landing, 023 i18n, 026 connect, 029 privacy, 032 admin)

## ⚠️ DELEGATION ZORUNLU
- Demo seed sample data (license/audit/event) → kendi yazılabilir (kısa)
- UI text/marketing copy → ask "..." qwen32b
- Hook BLOCK 5000+ char aktif

## 0. Bağlam

Müşteri toplantısı yaklaşıyor. Kullanıcı (Enes) ekran paylaşıp **panel üzerinde canlı** demo yapacak. Mevcut panel'de:
- Landing, Status, Setup wizard, Connect dashboard, Privacy, Admin (032 sonrası), Ana Panel mevcut
- AMA demo'yu **gerçekçi** ve **etkileyici** yapacak parçalar eksik:
  - Sahte ama gerçekçi data yok (boş panel kötü görünür)
  - Mock provider mode yok (canlı API rate limit / latency riski)
  - MCP tool browser yok (121 tool listesi sadece API'de)
  - Provider cascade visualizer yok (request flow görünmüyor)
  - Live SSE event stream görselleştirme yok
  - Demo Mode banner yok ("Bu canlı kullanım değil, gösterim" işareti)

033 — bu eksiklikleri kapatır. Toplantıdan önce demo "wow" seviyesinde.

---

## 1. Amaç (DoD)

- [ ] **Demo Mode** sistem-genelinde toggle (`ABS_DEMO_MODE=true`)
- [ ] **Demo Seed Script** — sahte gerçekçi data (license, audit, beta requests, webhook events, usage metrics)
- [ ] **Mock Providers Profile** — `docker-compose.demo.yml` (Anthropic/Stripe/Slack/GitHub mock httpx response)
- [ ] **Demo Mode UI Banner** — panel header'da "🎬 DEMO MODE — Sample data only" yumuşak banner
- [ ] **MCP Tool Browser Panel** — `/static/panel/tools.html` (121 tool grid + filter + search + detail modal)
- [ ] **Provider Cascade Visualizer** — `/static/panel/cascade.html` (request flow diagram, son 100 request)
- [ ] **Live SSE Event Stream Widget** — panel'de yan kolon (scroll list + 7 event tipi filter)
- [ ] **Quality Pipeline Step Viewer** — `/static/panel/pipeline.html` (3-model zinciri timeline)
- [ ] **i18n Switcher Polish** — header üst-sağda her sayfada (EN/TR/ES toggle)
- [ ] **Screenshot Generator** — `infra/scripts/generate_demo_screenshots.py` (Playwright headless, 8 ekran × desktop+mobile)
- [ ] **Demo Video Script** — `docs/demo/video-script.md` (5-7 dk Loom outline)
- [ ] **MCP tool:** `demo_status` — demo mode aktif mi, seed data version
- [ ] 30+ yeni test, pytest 637 → ~670
- [ ] vitest 39 → 44 (5 yeni: tool browser, cascade viz, SSE stream, pipeline viewer, lang switcher)
- [ ] Tool count 121 → 122
- [ ] 6 smoke evidence

---

## 2. Modüller

### Modul A — Demo Mode Toggle
**Yeni:** `app/config.py` patch + `app/middleware/demo_mode.py`
- `settings.demo_mode: bool = False` (env `ABS_DEMO_MODE`)
- Middleware: response header `X-ABS-Demo-Mode: true` ekle
- API `/v1/demo-mode/status` → `{enabled: bool, seed_version: str, started_at: ts}`
- Frontend (Next.js + static panels): demo mode yes ise üst banner

3 test (`test_demo_mode_toggle.py`).

### Modul B — Demo Seed Script
**Yeni:** `infra/scripts/seed_demo_data.py` (~250 satır)
- Çağrı: `python infra/scripts/seed_demo_data.py --reset` (önce mevcut sil)
- Üretir:
  - **5 sample license** (different tiers, customer_id_stripe='demo:...')
  - **20 webhook events** (checkout.session.completed × 5, charge.refunded × 2, ignored × 13)
  - **50 customer audit log entries** (login, license_activate, key_added, vb.)
  - **15 wizard events** (6 step funnel — bazı drop)
  - **8 beta requests** (3 approved, 5 pending)
  - **30 vault audit entries** (encrypt/decrypt/rotate)
  - **3 connected services** (GitHub, Slack, OpenAI — vault encrypted dummy)
  - **120 feature usage entries** (race, cascade, qual_pipeline, vb. — geçen 7 gün dağılım)
- Output: `data/demo_seed_v1.json` (versionlu)
- Idempotent: `--reset` flag yoksa skip if seed_version match
- 5 test (`test_demo_seed.py`)

### Modul C — Mock Providers Profile
**Yeni:** `infra/docker-compose.demo.yml`
- Override: `services.abs-backend.environment` includes `ABS_PROVIDER_MOCK=1`
- Yeni env handler: `app/providers/mock.py` — httpx mock middleware:
  - Anthropic: 200ms latency, "Lorem ipsum..." response
  - Stripe: webhook event simulator
  - GitHub OAuth: instant approve
  - Slack: post return success
  - Cohere: rerank static response
- 4 test (`test_mock_providers.py`)

### Modul D — Demo Mode UI Banner
- `core/landing/components/DemoBanner.tsx` (Next.js sayfaları için)
- `app/static/panel/_demo_banner.html` (vanilla static panels için, JS injection)
- Banner: "🎬 Demo Mode — sample data, not live customers" sticky top
- Brand colors (Automatia mavi)
- 2 vitest (frontend) + 1 backend test

### Modul E — MCP Tool Browser Panel
**Yeni:** `app/static/panel/tools.html` + `app/api/panel/tools.py`
- `GET /v1/panel/tools` — 121 tool listesi (gen_api_reference verisi gibi):
  - name, description (docstring), category (provider/quality/fullstack/RAG/...), params
- HTML grid 4 kolon, kategori chip'leri, search input
- Click → modal: full description, example prompts, last_used_at, success_rate
- 4 test (`test_panel_tools.py`)

### Modul F — Provider Cascade Visualizer
**Yeni:** `app/static/panel/cascade.html` + `app/api/panel/cascade.py`
- `GET /v1/panel/cascade/recent?limit=100` — son 100 request:
  - timestamp, prompt_hash, cascade_path (gptoss → kimi → gemini), latency_per_step, total_latency, winner
- HTML: timeline view (sankey-style mermaid.js), CSV export
- 4 test (`test_cascade_visualizer.py`)

### Modul G — Live SSE Event Stream Widget
- Patch `app/api/stream.py` — `EventSource /v1/sse/all` event tipi 7
- `app/static/panel/_sse_widget.html` (panel'e iframe veya inline)
- 100 entry rolling buffer, filter dropdown (license/billing/telemetry/rag-update/...)
- Color-coded (success green, error red, info blue)
- 3 test (frontend SSE consume + filter + buffer)

### Modul H — Quality Pipeline Step Viewer
**Yeni:** `app/static/panel/pipeline.html` + `app/api/panel/pipeline.py`
- `GET /v1/panel/pipeline/recent?limit=20` — son 20 qual_code/qual_tr çağrısı
- Her çağrı: model 1 (üret) → output → model 2 (doğrula) → output → model 3 (düzelt) → final
- HTML: collapsible timeline her step (model name, latency, output preview)
- 4 test

### Modul I — i18n Switcher Polish
- Tüm panel sayfalarında üst-sağ köşede dil seçici (EN/TR/ES dropdown)
- Cookie persist (NEXT_LOCALE)
- Mevcut 023 i18n locale dosyaları reuse
- 3 vitest (her sayfa render + switch + persist)

### Modul J — Screenshot Generator
**Yeni:** `infra/scripts/generate_demo_screenshots.py` (~150 satır)
- Playwright headless Chrome
- 8 ekran × 2 viewport (1920x1080 + 375x812):
  - Landing, Status, Setup wizard (step 0,3,6), Panel, Connect, Privacy, Admin, Tools browser
- Output: `docs/demo/screenshots/<screen>_<viewport>.png`
- README'da otomatik insert
- 1 test (`test_screenshot_generator.py` — script syntax + path)

### Modul K — Demo Video Script
**Yeni:** `docs/demo/video-script.md` (~600w EN+TR, delegate gptoss/qwen32b)
- 5-7 dakikalık Loom outline:
  - 0:00-0:30 Hook + value prop
  - 0:30-1:30 Landing + Pricing
  - 1:30-3:00 Setup wizard hızlandırılmış
  - 3:00-5:00 Ana panel + canlı MCP demo
  - 5:00-6:30 Privacy/Admin/Compliance
  - 6:30-7:00 Closing CTA
- Camera prompt suggestions, voice tone, transitions
- 1 test (markdown sections + min 500w)

### Modul L — `demo_status` MCP Tool
**Yeni:** `app/mcp/tools/demo_tools.py`
- `demo_status()` → `{demo_mode: bool, seed_version, mock_providers: bool, screenshot_paths: list, video_path: str|null}`
- 2 test
- Tool count 121 → **122**

---

## 3. Test Stratejisi (30+ test)

| Modül | Test |
|---|:-:|
| A demo mode | 3 |
| B seed script | 5 |
| C mock providers | 4 |
| D banner (frontend) | 2 vitest + 1 backend |
| E tool browser | 4 |
| F cascade viz | 4 |
| G SSE stream (frontend) | 3 vitest |
| H pipeline viewer | 4 |
| I i18n switcher (frontend) | 3 vitest |
| J screenshot gen | 1 |
| K video script | 1 |
| L demo_status MCP | 2 |
| Tool count guard | 1 update |
| **TOPLAM** | **30 backend + 8 frontend** |

Backend: 637 → **667** (+30). Frontend: 39 → **47** (+8). Tool: 121 → **122**.

---

## 4. Smoke Evidence (`/tmp/abs-033-smoke/evidence/`)

1. `01_demo_mode_toggle.json` — env toggle + middleware header
2. `02_seed_demo_data.json` — sample data inventory (counts per type)
3. `03_mock_providers.json` — 5 provider mock response shape
4. `04_tool_browser.json` — 121 tool grid + categories
5. `05_cascade_visualizer.json` — recent 100 request flow
6. `06_screenshot_paths.json` — 16 screenshot dosya path

---

## 5. Adım Adım

```
1. baseline pytest 637 + tool 121 + vitest 39
2. Modul A: demo mode toggle + middleware + 3 test
3. Modul B: seed script + 5 test (sample data tüm tablolar)
4. Modul C: mock providers profile + 4 test
5. Modul D: demo banner UI + 2 vitest + 1 backend
6. Modul E: tool browser HTML + API + 4 test
7. Modul F: cascade visualizer + 4 test
8. Modul G: SSE stream widget + 3 vitest
9. Modul H: pipeline viewer + 4 test
10. Modul I: i18n switcher + 3 vitest
11. Modul J: screenshot generator + 1 test
12. Modul K: video script (gptoss + qwen32b ~600w) + 1 test
13. Modul L: demo_status MCP + tool 121→122 + 2 test
14. 6 smoke evidence
15. summary + completed/
16. memory snapshot 033
17. Final demo readiness checklist (`docs/demo/checklist.md`)
```

## 6. DoD

```
[ ] 12 modül A-L tamam
[ ] pytest 667 (+30)
[ ] vitest 47 (+8)
[ ] tool 122 (+1)
[ ] 6 smoke evidence
[ ] regression sıfır (010-032)
[ ] 16 screenshot (8 ekran × 2 viewport) docs/demo/screenshots/
[ ] Demo Mode banner her sayfada görünür (toggle ile)
[ ] Seed script idempotent + version
[ ] Mock providers tam (Anthropic/Stripe/Slack/GitHub/Cohere)
[ ] summary + completed/
[ ] memory snapshot 033
```

## 7. Notlar

1. **Demo Mode banner intrusive olmasın** — sticky top 30px height, dismiss-able, brand renkler (Automatia mavi).
2. **Seed data realistic** — fake email lorem değil, "demo+stripe@meetingco.test" gibi prod-like.
3. **Mock providers latency** — gerçekçi (Anthropic 800-1200ms, Groq 200-400ms, Cerebras 100-300ms).
4. **MCP tool browser** — kategori chip'leri renk-kodlu (provider mavi, quality yeşil, fullstack mor).
5. **Cascade visualizer mermaid.js** CDN'den (offline mode için bundle yedekle).
6. **Screenshot generator** Playwright browser cache reuse (build hızlandırma).
7. **Video script** Loom-friendly: pause noktaları + voice tone hint + screen capture coordinates.
8. **i18n switcher** localStorage cookie + URL param (`?lang=tr`) — kalıcı.
9. **Memory snapshot:** task sonu `session_resume_state_20260427_033.md` veya tarih ne olursa.
10. **Toplantı tarihi:** 033 bitince → kullanıcı ile koordineli demo + provası.
