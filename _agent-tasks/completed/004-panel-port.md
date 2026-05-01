# Task 004 — Panel Port: SERVER → Ürün

## Bağlam

SERVER'da olgun, **7550 satır** panel HTML var (`automatiabcn_panel_v2.html`, D hybrid). 8 widget + SSE stream (5 event) + cosmos neural graph + sparkline'lar + senior judge + cache counter + budget tracker + workflow + cohere alert. 6 ay geliştirilmiş, production-proven.

Bu task SERVER panel'ini **ürüne taşır**. SERVER dokunulmaz (Read-only). Ürün için:
- Hardcoded path'ler → env-var + tenant-aware
- Panel-api endpoint'leri → ABS backend endpoint'leri (001+002+005'ten gelenler)
- 3 cihaz referansları (PC/M4/iPad) → tek sunucu görünümü
- Auth wrapper (tek kullanıcı için de, giriş olmadan panel gösterilmez)
- Custom branding hook (Automatia logo → ileride müşteri logosu)

**Bağlı docs:**
- `docs/architecture.md` § 2 + § 3 (Bileşenler, endpoint'ler)
- `docs/operations.md` § 4 (müşteri serviste health monitor)
- `docs/design-decisions.md` § 22-24 (watchdog + cascade)
- `docs/research/landing-onboarding.md` § 3 (features — panel widget listesi)

**Kaynaklar (SERVER'dan OKU, KOPYALAMA — ADAPT):**
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/automatiabcn_panel_v2.html` (**7550 satır** — chunk-based read zorunlu, LLM context sığmaz)
- `/Users/eneseserkan/panel-api/server.js` (2650 satır — referans, FastAPI'ye port edilecek — ama 005 task'ında, bu task sadece HTML)

## Giriş (Mevcut Durum — 003 sonrası)

- `core/backend/` — FastAPI + licensing + webhook (001+002)
- `core/landing/` — Next.js landing + pricing (003)
- Panel için **yeni yapı**: `core/backend/app/static/panel/`

## Kritik Mimari Kararı

Panel 2 yaklaşımdan hangisi?

| Yaklaşım | Artı | Eksi | Karar |
|---|---|---|---|
| **A) FastAPI static serve** | SERVER ile 1:1 port, hızlı, değişiklik az | Vanilla JS sürdürme | ✅ **Seçili** |
| B) Next.js rewrite | Modern stack, shadcn/ui uyum | 6-8 hafta iş, SERVER ile sync zor | ❌ Ertelendi |

**Panel'i vanilla JS olarak koruyoruz** çünkü:
1. 7550 satır olgun kod, yeniden yazmak kayıp
2. SERVER'daki değişiklikleri ürüne taşımak kolay (HTML diff)
3. Next.js sadece landing için (003), panel FastAPI static
4. Gelecekte Next.js'e migrate edilebilir (`004b-panel-migrate.md` — henüz yok)

## Beklenen Çıktı

### 1. FastAPI Static Mount (`core/backend/app/`)

- [ ] `app/static/panel/index.html` — SERVER panel'den port (7550 satır → tahmini 7400 satır, bazı bölümler kaldırılacak)
- [ ] `app/static/panel/assets/` — gerekli statik asset'ler (varsa SVG logo, font)
- [ ] `app/api/panel.py` — panel altında çağrılan endpoint'ler (çoğu 001+002+005'te zaten var, bu task sadece static mount + auth wrapper)
- [ ] `app/main.py` güncelle — `StaticFiles` mount `/panel` altında + auth dependency

### 2. Auth Wrapper (MVP — single-user)

- [ ] `app/api/auth.py` — basit admin auth:
  - `POST /auth/login` — admin email + parola → JWT session cookie (HTTPOnly, SameSite=strict)
  - `POST /auth/logout` — cookie sil
  - `GET /auth/me` — session doğrula, user info dön
  - Dependency: `current_admin()` — FastAPI DI, protected route'larda kullan
- [ ] `app/static/panel/login.html` — basit login sayfası (email + parola + submit)
- [ ] `core/backend/pyproject.toml` — `passlib[bcrypt]`, `python-jose[cryptography]` ekle
- [ ] Admin kullanıcı ilk kurulumda setup wizard'dan oluşturulur (005'te) — bu task'ta hard-coded "admin@local" placeholder OK, 005'te DB'ye bağlanır

### 3. Panel HTML Adaptasyonları

SERVER panel'den port sırasında yapılacaklar:

**3a. Hardcoded path'ler + URL'ler:**
- `100.100.110.44` (PC LAN IP), `192.168.1.41` (iPad IP), `100.100.19.20` (M4 Tailscale) → **tek sunucu**, kendisi
- `http://localhost:8889/api/...` → `/api/...` (backend aynı origin'de)
- `http://192.168.1.44:8888/api/...` → `/api/...`
- `/Users/eneseserkan/...` path referansları → **sil** (panel'de görünen metin)
- `ai-pc`, `M4-Ollama`, `iPad` cihaz label'ları → **sil veya generic** ("Server", "Yerel Model")

**3b. 3-cihaz mimarisi referansları:**
- "PC GPU" widget → "Yerel GPU" (opsiyonel, GPU yoksa gizle)
- "M4 Ollama" bölümü → kaldır veya "Yerel Model" + varsayılan kapalı
- "iPad Monitor" referansları → kaldır
- "Tailscale" terminolojisi → kaldır
- Cosmos neural graph içindeki 3-cihaz arcs → **tek cihaz + provider arcs** (Anthropic + Groq + Cerebras + Gemini + CloudFlare + Cohere)

**3c. Branding:**
- Automatia logo (mevcut panel'de var) → **koru**, `public/logo.svg` path'ten
- "Automatia BCN" başlığı → "Automatia ABS" veya müşteri admin_email prefix'i
- Renk teması: mevcut brand palette korunur (slate/zinc + accent)
- Gelecek custom branding için CSS variable: `--brand-primary` config'ten okunabilir (004b)

**3d. Kaldırılacak bölümler:**
- Bizim-özel test/debug widget'ları (varsa, bu task sırasında tespit)
- Hardcoded "Enes" referansları → generic veya `current_admin.name`
- Private URL'ler (sshfs mount gibi) → sil

**3e. Korunacak 8 widget (tam parity):**
1. Cosmos neural graph — provider bazlı (6 sağlayıcı)
2. Sparkline widgets (DELEGATION, CACHE HIT, GPU temp opsiyonel, BÜTÇE)
3. Senior Judge widget (skor timeline + teaching)
4. Workflow durability widget (son 5 workflow + resume)
5. Cohere alert banner (threshold'lar)
6. Provider status (6 provider health)
7. MCP tool kullanım (tools count + last activity)
8. Budget tracker (günlük + tahmini)

### 4. SSE Stream Port

- [ ] `app/api/stream.py` — `/stream` SSE endpoint (aynı 5 event type: metrics, orchestrator, cohere-usage, mcp-tools, quota-status, budget-today)
- [ ] Panel HTML'de `EventSource(BASE + '/stream')` → URL değişir (`BASE = ''` — aynı origin)
- **Not:** Bu event payload'lar 005-orchestrator'dan gelecek, **bu task sadece stream shell** (005'teki endpoint'lerin aynı sözleşmeyi karşılaması için). MVP için placeholder data OK.

### 5. Test

- [ ] `tests/test_panel.py`:
  - `test_panel_requires_auth()` — `/panel` GET without session → 401 veya redirect `/login`
  - `test_login_flow()` — valid creds → cookie set, `/panel` 200
  - `test_panel_html_rendered()` — GET `/panel` (with auth) → HTML body içinde "Automatia ABS" geçiyor
  - `test_panel_critical_ids_present()` — DOM kontrolleri (cosmos, widget ID'leri — SERVER pytest pattern'i taşı)
- [ ] Playwright opsiyonel (003'teki gibi panel render ekran görüntüsü)

## Kısıtlar

- ❌ SERVER klasörüne **Write/Edit yasak** (freeze-dir aktif) — sadece Read
- ❌ Next.js rewrite (gelecek task)
- ❌ Mevcut widget'ların özelliklerini kaybetme (feature parity zorunlu)
- ❌ Marketing dili ("AI'ın kalbi", "devrim") — panel teknik dashboard
- ✅ FastAPI `StaticFiles` mount
- ✅ JWT session cookie (HTTPOnly + SameSite=strict + Secure prod'da)
- ✅ bcrypt parola hash
- ✅ Tüm widget ID'leri ve CSS class'ları **korunmalı** (SERVER'daki panel_smoke testi pattern'leri ürüne de uygulanabilsin)
- ✅ pytest + Playwright opsiyonel

## Delegation Yönergesi (ZORUNLU)

**Bu task'ın en büyük zorluğu: 7550 satır HTML context limit'ine sığmaz.** Pragmatik chunk stratejisi:

### 1. Önce SERVER panel'i keşfet

```
Read /Users/eneseserkan/Main/Automatia BCN/SERVER/automatiabcn_panel_v2.html
  limit=100 (ilk 100 satır — head + body başlangıç)

Read sistemi section-by-section:
- Satır 1-200: <head>, meta, CSS
- Satır 200-2000: header + nav + cosmos hybrid + cosmos strip
- Satır 2000-3500: widget'lar (senior judge, workflow, cohere alert, budget, cache)
- Satır 3500-5500: CSS (styling)
- Satır 5500-7550: JS (fonksiyonlar, SSE, polling, render)
```

Bu read'leri tek tek yap, her chunk'ı özetle anla.

### 2. SERVER panel widget pattern'leri için RAG

```
mcp__abs__rag_query "cosmos hybrid panel sparkline sse javascript"
mcp__abs__rag_query "senior judge widget panel canvas draw"
mcp__abs__rag_query "panel auth login fastapi jwt cookie"
```

### 3. HTML adaptasyon için `qual_code`

Her büyük bölüm için ayrı çağrı (TPM limit):

```
mcp__abs__qual_code
  prompt: "Bu HTML+JS kodu SERVER dashboard'dan. Adapte et:
  [SERVER kod chunk'ı, ~300 satır]
  Değişiklikler:
  - Hardcoded IP/host → relative URL
  - 3-cihaz label → single server
  - `/Users/eneseserkan/...` referansları sil
  Widget'ların davranışını koru."
```

### 4. Auth için `fullstack be`

```
mcp__abs__fullstack
  layer: "be"
  prompt: "FastAPI JWT session auth:
  - POST /auth/login — email + pw → bcrypt verify → JWT cookie
  - POST /auth/logout — cookie sil
  - GET /auth/me — session doğrula
  - current_admin() dependency
  Kısa prompt, TPM'e dikkat."
```

### 5. Testler için `qual_code` (write_tests'in alternatifi)

```
mcp__abs__qual_code
  prompt: "pytest + httpx ile:
  - test_panel_requires_auth, test_login_flow, test_panel_html_rendered,
  - test_panel_critical_ids_present (HTML body'de cosmos-hybrid, senior-judge, workflow-card ID'lerini ara).
  Mock AuthenticationBackend, httpx AsyncClient."
```

### 6. Playwright live render (003'teki gibi)

```
mcp__playwright__browser_navigate → http://localhost/panel (login sonrası)
mcp__playwright__browser_take_screenshot → panel-home.png
```

### 7. Final skor

```
mcp__abs__code_review tier="standard" (auth modülünü özellikle)
mcp__abs__judge_patch (auth + panel HTML diff)
```

### Hedef Delegation

- En az **%35 delegation** — büyük task, yüksek delege
- MCP çağrı **min 10 kez**
- RAG query en az **3 kez** (SERVER patterns için)

## Adımlar

1. `core/backend/app/static/panel/` klasörü oluştur
2. SERVER panel'i **chunk-by-chunk Read** (5-7 chunk)
3. `rag_query` ile panel pattern'leri ara
4. HTML adaptasyon — her bölüm için `qual_code` delege
5. Auth modülü — `fullstack be` delege
6. `app/main.py` güncelle: StaticFiles mount + auth router + session middleware
7. Test yazımı — `qual_code` delege
8. `npm run build` (landing değişmedi, skip) + `pytest` yeşil
9. Playwright live render screenshot
10. `code_review` + `judge_patch` final
11. Summary yaz

## Doğrulama

```bash
cd core/backend

# 1. Install yeni deps
.venv/bin/pip install -e ".[dev]"

# 2. Test
.venv/bin/pytest tests/ -q
# Beklenen: önceki 12 + yeni 4 = 16 passed

# 3. Docker build
cd ../../infra
docker compose build backend

# 4. Up
docker compose up -d

# 5. Login flow
curl -k -X POST https://abs.local/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@local","password":"CHANGEME"}' \
  -c cookies.txt
# Beklenen: 200, cookie set

# 6. Panel erişim
curl -k -b cookies.txt https://abs.local/panel
# Beklenen: 200, HTML body'de "Automatia ABS"

# 7. Panel auth'suz
curl -k https://abs.local/panel
# Beklenen: 401 veya redirect /login

# 8. Panel widget ID'leri
curl -k -b cookies.txt https://abs.local/panel | \
  grep -E "cosmos-hybrid|workflow-card|judge-body|cohere-alert-banner|spark-deleg"
# Beklenen: hepsi bulunur
```

## Tamamlama

1. `git diff --stat` al — değişen satır sayısı
2. `judge_patch` skor (hedef >= 7)
3. `completed/004-panel-port-summary.md`:
   ```markdown
   ## Ne Yapıldı
   - Panel HTML port: SERVER 7550 satır → ürün X satır (kaldırılan/değişen Y satır)
   - Auth modülü: N dosya, M satır
   - Test: K passed

   ## Kaldırılan Bölümler
   - 3-cihaz referansları (PC/M4/iPad)
   - Hardcoded absolute path'ler
   - Private URL'ler
   - [liste]

   ## Korunan Widget'lar (8)
   - Cosmos, sparkline, senior judge, workflow, cohere, provider, mcp-tools, budget

   ## Delegation Kullanımı
   - Read (SERVER): N chunk × M satır
   - rag_query: N
   - qual_code: N (her bölüm için)
   - fullstack be: N (auth)
   - code_review, judge_patch: ...
   - Toplam delegation: %X (hedef %35+)

   ## Playwright Doğrulama
   - Screenshot: panel-home.png
   - Widget render durumu

   ## Eksik / Blocker
   - SSE stream placeholder (005'te gerçek event payload)
   - Admin user DB (005'te setup wizard)
   - Custom branding config (004b, gelecek)
   ```
4. Task'ı `completed/`'e taşı
5. Planlayıcıya "004 tamam" rapor et

---

**Tahmini süre:** 4-6 saat (en büyük task, 7550 satır port)
**Sonraki task:** `005-orchestrator.md` — 75 MCP tool + 5 hook + 13 pipeline port (en karmaşık, ama chunk-based stratejiyi burada öğreneceğiz)
