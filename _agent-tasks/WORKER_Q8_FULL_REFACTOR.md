# WORKER Q8 — Full UX Refactor + Customer Journey Working

> **Tetikleyici:** Founder (2026-05-01) sistemi fresh kurdu, sayfa-sayfa gezdi:
>   - `/panel` cosmos berbat, neural graph mantığı yok
>   - `/panel/chat` **YOK** (kritik — AI ile yazışma yeri yok)
>   - `/panel/tools` **YOK** (122 tool API var ama UI yok)
>   - `/admin/workflow-builder` **runtime crash** (estimateCostCents undefined)
>   - Provider cascade / Quality pipeline / Tool browser amatör
>   - **Sonuç:** Hiçbir akış çalışmıyor, ürün satılamaz
> **Hedef:** Komple UX refactor + müşteri akışları gerçekten çalışacak + verification standartı yükseltilecek
> **Branch:** `feat/sprint-q8-refactor` (master'dan)

---

## 0. Architectural Decisions (önce bunlar)

### A1. Tek Workspace + Role-Based Reveal

**Karar:** Linear/Notion modeli — tek `/workspace` (veya `/panel`), role'e göre menü reveal.

| Persona | URL | Görür |
|---------|-----|-------|
| End-user (marketing/sales) | `/panel` | Chat + Workflows + Meetings + Tools + Quota |
| Admin (CTO) | `/panel` | Aynısı + Settings, Audit, Users, Provider config |

Cmd+K command palette her şeye erişim sağlar. Permission-gated menu items.

### A2. Chat UI ZORUNLU — Claude Code OPSIYONEL

**Karar:**
- **Browser chat UI** = ana arayüz (KOBİ ekibi, teknik olmayan)
- **Claude Code MCP server** = opsiyonel (developer/CTO için)
- ABS = MCP server, Claude Code `claude mcp add --transport http abs http://customer-server:8000/mcp` ile bağlanır

**Trade-off matrix:**

| Yetenek | Browser Chat | Claude Code |
|---------|--------------|--------------|
| Multi-tenant izolasyon | ✅ | ⚠ (tek kullanıcı) |
| Teknik olmayan kullanıcı | ✅ | ❌ |
| File system access | ❌ | ✅ |
| Git operations | ❌ | ✅ |
| Local shell exec | ❌ | ✅ |
| IDE integration | ❌ | ✅ |
| Slash commands (/rag, /workflow) | ✅ | ✅ (MCP sayesinde) |
| Workflow trigger | ✅ | ✅ |
| Tool envanter visualizasyon | ✅ | ❌ (CLI text) |
| Marketplace install | ✅ | ⚠ (komut ile) |
| Real-time collaboration | ✅ | ❌ |
| Audit log per tenant | ✅ | ⚠ |
| Cost discipline (free path görünür) | ✅ | ❌ |

**Hibrit yaklaşım:**
- ABS backend = MCP server expose (`/mcp` endpoint)
- ABS frontend = chat UI (Vercel AI SDK)
- Müşteri CTO Claude Code'a `claude mcp add` ile bağlar
- Müşteri ekibi browser'dan chat UI'ya gelir
- **Aynı tenant, aynı cascade, aynı history** (DB-backed)

### A3. Cosmos Kaldır → Neural Graph (Force-Directed)

**Karar:** Cosmos parallax tamamen kaldırılır. Yerine **react-force-graph-3d** ile canlı neural graph:
- Düğümler: Provider (6) + MCP tool (122) + Workflow (n) + RAG doc (n)
- Edge'ler: cascade calls (real-time animated), tool dependencies, workflow flow
- **Live data:** her cascade çağrısı → animasyonlu edge highlight (1.5s fade)
- Filters: by category, by tenant, time range
- Referans: Obsidian Graph View

### A4. Verification Disiplini (Yeni Standart)

**"PASS" yalnızca bunlar geçerse:**
1. Backend endpoint 200 ✅ (mevcut)
2. **Frontend UI gerçekten render** (HTML byte > 100KB skeleton dışı)
3. **Customer flow tamamlanıyor** (Playwright headed: tıklama → sayfa → veri görünür)
4. **Console error 0** (browser dev tools)
5. **Screenshot proof** her exit gate'de

Repro `curl /v1/.../health 200` yetmez — Playwright headed e2e zorunlu.

---

## 0.5 — Frontend Audit Bulguları (2026-05-01 Founder Walkthrough Sonucu)

15 sayfa baştan sona Playwright + manuel test edildi. Tam bulgu listesi: `SERVER/UX_BUGS_20260501.md` (44 bulgu, kategorize). Worker brief'i bu bulgulara çözüm üretmek zorunda. Özet:

### 🔴 8 sayfa hiç YOK (404)
| Sayfa | URL | Neden Kritik |
|-------|-----|--------------|
| Chat UI | `/panel/chat` | Ana use-case (AI sohbet) — ürün satılamaz |
| Tool Browser | `/panel/tools` | 122 MCP tool envanteri görünmüyor |
| Provider Cascade | `/admin/providers` | 6 provider durumu / fallback chain GUI yok |
| Quality Pipelines | `/admin/pipelines` | qual_code/qual_tr/race UI'da trigger edilemiyor |
| RAG | `/admin/rag` | Doküman upload, sorgu test imkansız |
| Knowledge Graph | `/admin/graph` | Q7 "Neo4j live" boş söz, UI yok |
| Settings | `/admin/settings` | Self-service config imkansız (license/vault/branding) |
| Multi-Admin Users | `/admin/users` | Magic-link davet, role assign panel'den yapılamıyor |
| Audit | `/admin/audit` | GDPR/SOC2/KOBİ compliance audit trail görünmüyor |

> Her biri Q8 phase A/C/D/E/F/J/K içinde tasarlanmış. Worker bu sayfaları **route + UI + backend wiring + test** ile sıfırdan kurmalı.

### ⚠️ 6 sayfa var ama tutarsız/bozuk
| Sayfa | Kritik Bulgu |
|-------|--------------|
| `/panel` ana | Cosmos kaldırılmış ama metric'ler statik, CTA yok, sidebar 6 item (15 olmalı) |
| `/admin/workflow-builder` | **W1 RUNTIME CRASH** `lib/workflow.ts:82 wf.nodes.reduce` — synthesize boş → null pointer. Linear list, n8n canvas değil. |
| `/admin/marketplace` | Panel sidebar yok (landing layout), role kontrolü kırık ("Read-only" yanlış uyarı), 5 plugin (Q7'de 10 vaat), i18n EN-only |
| `/panel/meetings` | Çift nav (landing + panel), sidebar 9 sayfa eksik, hydration mismatch error, empty state CTA yok |
| `/panel/transcription` | Hardcoded TR-only TTS, mic permission pre-explanation yok, real-time waveform yok |
| `/panel/quota` | Tüm provider "yapılandırılmadı" + "Configure" CTA yok, bar chart yok, date range yok |

### Tüm Sayfalarda Ortak Sorunlar (Layout-Level)
1. **Çift nav:** Auth'd panel sayfalarında landing nav (Home/Showcase/Pricing/Beta) görünüyor → kafa karıştırıcı. `app/panel/layout.tsx` ve `app/admin/layout.tsx` landing chrome'unu exclude etmeli.
2. **Sidebar gap:** Sadece 6 nav item, oysa 15 olmalı. Worker sidebar'ı Q8 phase'ler bittikçe genişletmeli (Üretim / Operasyon / Toplantılar / Yönetim kategorize).
3. **i18n karmaşası:** Panel TR, marketplace EN. next-intl + locale dosyaları zorunlu (default `en`, `tr`, `es`).
4. **Theme toggle hydration mismatch:** next-themes SSR-CSR çakışması (`mounted` state pattern ile fix).
5. **Empty state çorak:** Tüm boş state'lerde CTA + illustration yok. Reusable `<EmptyState>` component zorunlu.
6. **Footer çorak:** Auth'd sayfalar landing footer (Özellikler/SSS/Kurulum rehberi) gösteriyor — kaldır.
7. **Status text yerine chip:** "Hazır" / "Idle" / "yapılandırılmadı" gibi text'ler shadcn/ui Badge variant'larıyla replace edilmeli.

### Q8 Hiçbir Phase Skip Edilemez
Audit sonucu: 14/15 sayfa "production-ready değil", 0 sayfa premium dashboard standardına yakın. Phase A → Q **eksiksiz** uygulanmadan müşteriye demo açılmamalı.

---

## 1. Phase A — Chat UI (CRITICAL, 16h)

### Sorun
`/panel/chat` HİÇ YOK. AI orchestration platform diyoruz ama AI ile konuşulamıyor.

### Deliverables

**Backend:**
1. `core/backend/app/db/models.py` extend:
```python
class ChatSession(SQLModel, table=True):
    id: int = Field(primary_key=True)
    tenant_slug: str = Field(index=True)
    user_email: str = Field(index=True)
    title: str = "Yeni sohbet"
    created_at: datetime
    updated_at: datetime

class ChatMessage(SQLModel, table=True):
    id: int = Field(primary_key=True)
    session_id: int = Field(foreign_key="chatsession.id")
    role: str  # user | assistant | system | tool
    content: str
    provider: Optional[str] = None  # which cascade provider answered
    tool_calls: Optional[str] = None  # JSON
    tokens_used: Optional[int] = None
    latency_ms: Optional[int] = None
    created_at: datetime
```

2. Alembic migration `0007_chat_sessions.py`

3. `core/backend/app/api/chat.py` (yeni):
```python
@router.post("/v1/chat/completions")
async def chat_completion(body: ChatRequest, admin = Depends(current_admin)):
    """Streaming SSE response, cascade router'ı tetikler."""
    # session_id varsa devam, yoksa yeni session
    # Cascade call (ollama → groq → cloudflare → ...)
    # Tool call detection: prompt slash command varsa execute
    # StreamingResponse SSE format

@router.get("/v1/chat/sessions")
async def list_sessions(admin):
    return await db.chat_sessions.where(tenant_slug=admin.tenant_slug).order_by(updated_at.desc()).all()

@router.get("/v1/chat/sessions/{id}/messages")
async def session_messages(id, admin):
    return await db.chat_messages.where(session_id=id).order_by(created_at).all()

@router.delete("/v1/chat/sessions/{id}")
async def delete_session(id, admin): ...
```

4. Slash command handler (`/rag`, `/workflow`, `/code`, `/translate`, `/analyze`):
   - `/rag <query>` → `/v1/rag/query` çağır, sonucu chat'e ekle
   - `/workflow <intent>` → workflow synthesize + execute
   - `/code <task>` → qual_code pipeline
   - `/translate <text>` → qual_translate
   - `/analyze <topic>` → qual_analysis 3-perspective

**Frontend:**
1. `core/landing/app/panel/chat/page.tsx` + `[id]/page.tsx`
2. **Stack:**
```bash
npm install ai @ai-sdk/react react-markdown remark-gfm rehype-katex rehype-prism-plus
```

3. UI bileşenleri (`components/chat/`):
   - `ChatLayout.tsx` — sidebar + main + ⌘K
   - `ChatSidebar.tsx` — session list, search, "+New" button
   - `ChatMessages.tsx` — virtualized list (`react-virtuoso`)
   - `MessageBubble.tsx` — markdown + KaTeX + syntax highlight + tool call card
   - `MessageInput.tsx` — textarea + slash autocomplete + file drop + send
   - `ToolCallCard.tsx` — cascade'in seçtiği tool + provider chip + latency
   - `ProviderChip.tsx` — `groq | gemini | anthropic-mock` badge
   - `SlashCommandPalette.tsx` — cmdk dropdown

4. `useChat` hook (Vercel AI SDK):
```tsx
const { messages, input, handleInputChange, handleSubmit } = useChat({
  api: "/api/chat",
  onResponse: (res) => { /* tool call detection */ },
});
```

5. Next.js API proxy `app/api/chat/route.ts` — backend'e SSE forward

### Test
- Playwright headed: aç `/panel/chat`, mesaj yaz, gönder, streaming response geldi mi
- Slash command: `/rag müşteri sorusu` → RAG query çalıştı mı
- Provider chip görünüyor mu?
- Session save + reload (sidebar'dan eski session aç)
- File upload (drag-drop) → RAG ingest tetikleniyor mu
- Console error 0
- Screenshot proof

### Exit Gate
- `/panel/chat` 200 (auth login sonrası)
- HTML rendered > 200KB (skeleton değil)
- Mesaj gönderme + streaming response çalışıyor
- En az 5 mesaj test edildi (text + slash command + file)
- Sidebar session list dolu

---

## 2. Phase B — Workflow Builder Refactor (CRITICAL fix + premium UI, 12h)

### Sorun
W1: Runtime crash `estimateCostCents` undefined (synthesize boş döndü)
W2: Cascade synthesize JSON parse başarısız
W3: UI amatör, n8n/Zapier seviyesinde değil

### Deliverables

**Bug fix:**
1. `lib/workflow.ts:82` defensive: `wf?.nodes?.reduce(...) ?? 0`
2. `WorkflowChatPanel.tsx` error boundary + retry button
3. Backend `/v1/workflows/synthesize` JSON schema enforce — `response_format: {type: "json_schema"}` ile cascade'e zorla

**Premium UI:**
1. **react-flow (xyflow)** install:
```bash
npm install @xyflow/react reactflow
```

2. Layout:
   - Sol sidebar — node palette (Trigger, ABS Tool, Cerbos check, RAG query, Compose, HITL gate, Output) — drag-to-canvas
   - Üst toolbar — NL prompt input + Synthesize + Templates dropdown (50 KOBİ template)
   - Orta — Canvas (zoom, pan, mini-map, drag-to-connect)
   - Sağ — Inspector Sheet (seçili node parametreleri, JSON schema validation)
   - Alt — Dry Run · Save · Execute · Run History

3. Templates library — `tests/fixtures/workflow_templates_50.json`:
   - Marketing: 10 (blog → social, email campaign, lead capture)
   - Sales: 10 (lead enrich, follow-up, quote generator)
   - Support: 10 (email triage, FAQ bot, escalation)
   - Ops: 10 (status report, incident response, audit)
   - Tech: 10 (PR review, deployment, error monitoring)

### Test
- NL prompt yaz → synthesize → graph render (4-6 node)
- Node sürükle, edge çiz, parametre değiştir
- Dry Run → step plan + cost estimate
- Save → DB'ye kayıt
- Execute → Inngest queue + run history sidebar'da görünür
- Crash YOK (W1 fix doğrulandı)

### Exit Gate
Aynı zamanda `tests/personas/A10_workflow_lifecycle.py` PASS — synthesize → execute → poll → done.

---

## 3. Phase C — MCP Tool Browser (CRITICAL, 6h)

### Sorun
Sayfa hiç yok. 122 tool var ama müşteri raw JSON'a bakmak zorunda.

### Deliverables

`core/landing/app/panel/tools/page.tsx` (yeni):

**Layout:**
- Sol sidebar — kategori sidebar (provider:44, quality:16, judge:8, rag:5, vs) + counts + "All" filter
- Orta — TanStack Table (sortable, filterable, paginated, sticky header)
- Üst — cmdk command palette ("⌘K to search 122 tools")
- Sağ — Tool detail Sheet (slide-in)

**Tool detail içeriği:**
- Name (mono font)
- Description
- Category badge
- Input/output JSON schema (`react-json-view-lite`)
- "Try it" button → cascade run with this tool
- Usage stats (last 30d) — Tremor sparkline
- Related tools (cosine sim öneri)

**Stack:**
```bash
npm install @tanstack/react-table fuse.js react-json-view-lite
```

### Test
- Sayfa 200 (auth login sonrası)
- 122 tool listeleniyor
- Kategori filter çalışıyor
- Search (fuzzy) çalışıyor
- Tool detail sheet açılıyor
- "Try it" cascade çağrı tetikliyor → sonuç gösteriyor

### Exit Gate
HTML > 150KB, console error 0, full table sortable.

---

## 4. Phase D — Provider Cascade Visualization (4h)

### Sorun
Cascade chain görsel değil, hangi provider configured/missing/rate-limited belli değil.

### Deliverables

`core/landing/app/admin/providers/page.tsx`:

- **Visual chain** (Tremor BarList + custom flow indicator):
  - 6 kart (Anthropic, Groq, Cerebras, Gemini, Cloudflare, Cohere)
  - Her kartta: configured badge, last call timestamp, success rate, p95 latency
  - Rate limit göstergesi (kalan token / saat)
- **Real-time call animation** — son 10 cascade call yatay timeline'da akar
- **Per-provider quota bar** — Tremor ProgressBar
- **Mock mode toggle** — test için anthropic_mock_mode değiştirme
- **API key Add/Edit** — provider key giriş formu (sadece admin)

### Test
- 6 provider listed
- Configured/missing tag doğru
- Real-time call görünür (cascade endpoint hit ettiğinde animasyon)
- Mock toggle çalışıyor

---

## 5. Phase E — Quality Pipelines UI (4h)

### Sorun
Pipeline'lar (qual_code, qual_tr, qual_analysis, race_*) UI'da yok.

### Deliverables

`core/landing/app/admin/pipelines/page.tsx`:
- Pipeline list (6 qual + 4 race + judge ensemble)
- Her pipeline kartında: ne yapar, hangi modeller, son çalıştırma, başarı oranı
- "Run pipeline" form: input prompt + parametre + start button
- Result preview (markdown + cost + latency + per-model breakdown)
- History — son 50 run + filter

---

## 6. Phase F — RAG / Bilgi Tabanı UI (6h)

### Sorun
Kurumsal hafıza için sayfa yok.

### Deliverables

`core/landing/app/admin/rag/page.tsx`:
- **Doküman upload** — drag-drop multi-file (PDF/MD/TXT/DOCX)
- **Chunking config** — recursive vs semantic vs contextual
- **Sorgu test** — input + top_k + hybrid (dense+sparse) vs dense-only toggle
- **Sonuç visualizasyon** — top-N chunk + score + highlight
- **Tenant filter** — multi-tenant'sa hangi tenant'a yükle
- **Index stats** — toplam doküman, chunk count, vector size, p95 query latency

Backend endpoint'leri (zaten var: `/v1/rag/ingest`, `/v1/rag/query`).

---

## 7. Phase G — Marketplace Polish (3h)

### Sorun
Mevcut UI install button çalışıyor (Q3'ten) ama detay sayfa, uninstall, container status visible değil.

### Deliverables

`core/landing/app/admin/marketplace/page.tsx` polish:
- 5 plugin card (mevcut)
- Detay sayfa `/admin/marketplace/[id]/page.tsx`:
  - Cosign signature info
  - Sandbox profile (RAM, CPU, egress allowlist)
  - Permissions
  - Live container status (running/stopped/error)
  - Install/Uninstall button + confirmation
  - Logs viewer (Tremor TabList)

---

## 8. Phase H — Meetings + Transcription Premium (4h)

### Sorun
Sayfalar var (Q5'te eklendi) ama frontend skeleton. Auth render eksik.

### Deliverables

`core/landing/app/panel/meetings/page.tsx`:
- Audio upload (drag-drop, max 100MB, format validation)
- Meeting list (TanStack Table — date, duration, speakers, status)
- Detail sayfa: transcript viewer + speaker tag (renkli) + summary + action items + export (JSON/SRT/TXT)

`core/landing/app/panel/transcription/page.tsx`:
- Live mic recording (WebRTC `getUserMedia`)
- 5s chunked upload → backend `/v1/transcribe/stream`
- Real-time speaker diarize (renkli tag)
- Export (JSON/SRT/TXT)
- Coqui re-synthesize button (segment'i farklı sesle dinle)

---

## 9. Phase I — Quota Tracker UI (2h)

### Sorun
Q5'te mock UI var ama bar chart eksik, threshold marker yok.

### Deliverables

`core/landing/app/panel/quota/page.tsx`:
- 6 provider bar (Tremor ProgressBar) + Claude Plus
- 80% sarı, 95% kırmızı threshold marker
- Real-time auto-refresh (TanStack Query 30s polling)
- Per-provider drill-down (saatlik kullanım grafiği — Tremor AreaChart)
- Export → CSV/JSON

---

## 10. Phase J — Neo4j Graph UI (4h)

### Sorun
`/v1/graph/cypher`, `/v1/graph/ingest`, `/v1/graph/nl-query` API var ama UI yok.

### Deliverables

`core/landing/app/admin/graph/page.tsx`:
- **Cypher query editor** — Monaco Editor (`@monaco-editor/react`)
- **NL query input** — "Hangi kullanıcılar X firmasında çalışıyor?" → Cypher
- **Result visualization** — react-force-graph (node + edge)
- **Ingest form** — entity + relation upsert (JSON paste veya form fields)
- **Schema browser** — node labels + relationship types + property keys

---

## 11. Phase K — Settings + Audit + Multi-Admin (4h)

### Settings (`/admin/settings`):
- Tenant info (slug, name, created_at)
- Domain + SSL (Step 3 değişikliği)
- License info (jti, tier, seat_count, valid_until)
- Provider keys (CRUD)
- Theme + locale tercihleri

### Audit (`/admin/audit`):
- Audit log timeline (TanStack Table)
- Filter: actor, action, resource, time range
- HMAC chain verify button
- Error log (`/v1/admin/errors/recent`)
- Vault audit (`/v1/admin/vault/audit`)

### Multi-Admin (`/admin/users`):
- User list (TanStack Table)
- "Davet et" button → magic-link email gönder
- Role assignment (admin/member/viewer)
- Active sessions
- Sign-out button (per session)

---

## 12. Phase L — Cosmos → Neural Graph (4h)

### Sorun
P1 — cosmos berbat görünüyor, anlamsız.

### Deliverables

1. **Cosmos kaldır** — `core/landing/components/cosmos/*` sil
2. **react-force-graph-3d** install:
```bash
npm install react-force-graph-3d three
```
3. `core/landing/components/panel/NeuralGraph.tsx`:
   - Düğümler: Provider (6) + MCP tool (122) + Workflow (n) + RAG doc (n)
   - Edge'ler: cascade calls (real-time animated), tool dependencies
   - Live data: WebSocket veya SSE'den `cascade_call` events
   - Animation: edge highlight 1.5s fade
   - Filters: by category, by tenant, time range
   - Click node → side panel (detail)

---

## 13. Phase M — Cmd+K Command Palette (2h)

`cmdk` install + global `<CommandPalette>` component:
- ⌘K her sayfada açılır
- Action'lar:
  - "Go to ..." (rota navigation)
  - "Run ..." (cascade prompt, workflow synthesize)
  - "Search tool ..." (fuzzy)
  - "Search session ..." (chat history)
  - "Install plugin ..." (marketplace)
- Recent + Suggested sections
- Keyboard shortcuts kayıt (`?` ile yardım)

---

## 14. Phase N — MCP Server Endpoint (Claude Code Entegrasyon, 6h)

### Sorun
Müşteri CTO Claude Code'una `claude mcp add abs ...` ile bağlamak istiyor — bu endpoint yok.

### Deliverables

`core/backend/app/api/mcp_server.py`:
- HTTP transport MCP server (Anthropic spec)
- `GET /mcp/tools` — 122 ABS tool spec (JSON-RPC schema)
- `POST /mcp/tools/{name}/call` — tool invoke (cascade router üzerinden)
- `GET /mcp/resources` — RAG documents, workflow templates
- Auth: bearer token (per-tenant, /admin/users → "Generate MCP token" button)

**Müşteri kullanım:**
```bash
claude mcp add --transport http abs https://customer-server.com:8000/mcp \
  --header "Authorization: Bearer abs_token_xxx"
```

Sonra Claude Code'da:
```
> Bana son 10 müşteri sorusunu özetle
[Claude Code → ABS MCP → /mcp/tools/rag_query → results → answer]
```

### Dokümantasyon
`docs/MCP_INTEGRATION_GUIDE.md` yeni:
- Setup adımları
- Token generate
- Slash commands ABS chat ile aynı (slash → MCP tool call)

---

## 15. Phase O — End-to-End Customer Journey Gate (KRITIK, 4h)

### Hedef
**Yeni "PASS" tanımı.** Müşteri akışı gerçekten çalışıyor mu?

### Test (Playwright headed)

`tests/e2e/customer_journey_full.mjs`:
1. Fresh `docker compose down -v` + `up -d`
2. `/setup` 6-step wizard (otomatik fill)
3. `/panel/login` (admin@demo-acme.com)
4. **`/panel`** ana sayfa → neural graph render
5. **`/panel/chat`** → mesaj gönder → streaming response geldi mi
6. **`/admin/workflow-builder`** → NL prompt → Synthesize çalışıyor mu (W1 fix kanıt)
7. **`/panel/tools`** → 122 tool listesi + filter
8. **`/admin/marketplace`** → plugin install + container running kanıt
9. **`/panel/meetings`** → audio upload + transcript
10. **`/panel/quota`** → bar chart + threshold
11. **`/admin/graph`** → Cypher query çalışıyor

Her adımda:
- Screenshot proof (`/tmp/abs-cj/q8/N-page.png`)
- Console error 0
- HTML byte > 100KB
- Network request 4xx/5xx 0 (404 favicon hariç)

### Exit Gate
**11/11 step PASS = Q8 PASS.**

Eğer 1 tane FAIL → sprint kapanmaz.

---

## 16. Çalışma Şartı

**Sıralama:**
- Phase A (Chat) + Phase B (Workflow fix) + Phase C (Tools) **kritik üçlü**, paralel
- Phase D-K kısmen paralel
- Phase L (Neural Graph) — A'dan sonra (real-time data binding için)
- Phase M (Cmd+K) — son aşama
- Phase N (MCP) — bağımsız
- Phase O (Customer Journey Gate) — **HEPSI BİTTİKTEN SONRA**

**Tahmini:**
- Sequential: ~80 saat
- Paralel 4 worker: ~24 saat (3 iş günü)

**Branch:** `feat/sprint-q8-refactor`
**Commit format:** `feat(q8): phase<X> <component>`

**Worker model:** Opus 4.7 (1M context) ya da Sonnet 4.6 — ikisi de OK. Founder direktifi (2026-05-01): "delegasyonlarla halledelim, context dolunca zaten durur, cap koymayalım."

**Maliyet kontrolü token cap ile değil, delegation ile yapılır:**
- Kod üretimi %70+ MCP'ye delege: `mcp__abs__ask_kimi` / `ask_gptoss` / `fullstack` / `race_code` / `qual_code`
- Türkçe metin/i18n: `mcp__abs__ask_qwen32b`
- Component inspiration: `mcp__magic__21st_magic_component_builder`
- Code review her phase sonu: `mcp__abs__code_review` tier=standard
- Test/doc: `mcp__abs__write_tests` / `write_docs`
- Worker (Opus/Sonnet) sadece: Read, Edit, Write, git, Playwright, entegrasyon orchestration

Context dolunca otomatik dur, founder /resume ile devam ettirir. Phase atomic commit + audit summary update sayesinde resume edilebilir state var.

**Browser test ZORUNLU:** Her exit gate'de Playwright headed e2e + screenshot proof. `curl 200` yetmez.

---

## 17. Engelleyiciler

| # | Faz | Engel | Cevap |
|---|-----|-------|-------|
| 1 | A | Vercel AI SDK install | Otonom — `npm install ai @ai-sdk/react` |
| 2 | B | react-flow setup | Otonom — `npm install @xyflow/react` |
| 3 | L | react-force-graph-3d setup | Otonom — `npm install react-force-graph-3d three` |
| 4 | N | MCP server spec | Anthropic MCP HTTP transport docs (kod oluştururken referans) |
| 5 | O | Headed Playwright env | Otonom — Q1'den beri kurulu |

**Soru sorulacak engel YOK** — tümü autonomous.

---

## 18. Geçme Kriteri (Master Final)

| Faz | Hedef |
|-----|-------|
| A Chat UI | mesaj + streaming + slash command + 100KB+ render |
| B Workflow | crash YOK + n8n-seviye node editor |
| C Tools | 122 tool browser + filter + detail sheet |
| D Providers | visual chain + real-time call animation |
| E Pipelines | 6 qual + 4 race UI'da çalışıyor |
| F RAG | upload + query + result |
| G Marketplace | install/uninstall + container status |
| H Meetings | upload + transcript + diarize |
| I Quota | bar chart + threshold + auto-refresh |
| J Neo4j | Cypher editor + force-graph viz |
| K Settings | 3 alt sayfa working |
| L Neural Graph | cosmos kaldırıldı + force-directed live |
| M Cmd+K | global palette her sayfa |
| N MCP Server | `claude mcp add` ile bağlantı |
| O Customer Journey | 11/11 step Playwright PASS |

**Sprint kapanış:** Q8 master_audit_summary.md + 11 screenshot + customer journey video (60s).

---

## 19. Verification Standard (yeni norm)

**"PASS" derken:**
- ❌ "Endpoint 200" yetmez
- ❌ "Test dosyası yazıldı" yetmez
- ❌ "In-container mock test geçti" yetmez
- ✅ **Browser'da müşteri X yapabiliyor** (Playwright headed kanıt)
- ✅ **Console error 0**
- ✅ **HTML byte > 100KB** (skeleton değil)
- ✅ **Screenshot proof** her adımda

Önceki sprint'lerde yanılttık ("99/308 PASS, pilot ready") — gerçekte chat yok, tool browser yok, workflow crash. Q8'de bu standart kalıcı.

---

**Tahmini süre:** 80h sequential / **24h paralel 4 worker** ~ 3 iş günü
**Son güncelleme:** 2026-05-01 · Q8 full UX refactor brief v1

---

## 🔬 EK ARAŞTIRMA — Detaylı Teknik Referanslar (v2)

### Phase A — Vercel AI SDK Implementation Detayı

**Backend (FastAPI SSE):**

```python
# core/backend/app/api/chat.py
from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
import json, asyncio

router = APIRouter(prefix="/v1/chat")

@router.post("/completions")
async def chat(body: ChatRequest, admin = Depends(current_admin)):
    async def stream():
        # 1. Slash command detection
        if body.messages[-1].content.startswith("/rag "):
            query = body.messages[-1].content[5:]
            results = await rag_query(query, tenant=admin.tenant_slug)
            yield f'data: {json.dumps({"type":"tool-call","name":"rag_query","args":{"query":query}})}\n\n'
            yield f'data: {json.dumps({"type":"tool-result","name":"rag_query","result":results})}\n\n'

        # 2. Cascade router (free-path öncelik)
        async for chunk in cascade_stream(body.messages, tenant=admin.tenant_slug):
            yield f'data: {json.dumps({"type":"text","content":chunk.text,"provider":chunk.provider})}\n\n'

        yield 'data: [DONE]\n\n'
    return StreamingResponse(stream(), media_type="text/event-stream")
```

**Frontend (`useChat`):**

```tsx
// app/panel/chat/[id]/page.tsx
"use client";
import { useChat } from "@ai-sdk/react";
import { ChatLayout, MessageBubble, MessageInput, ToolCallCard, ProviderChip } from "@/components/chat";

export default function ChatPage({ params }: { params: { id: string } }) {
  const { messages, input, handleInputChange, handleSubmit, isLoading, error, stop, reload } = useChat({
    api: `/api/chat?session=${params.id}`,
    onFinish: (msg) => { /* toast cost + latency */ },
    onError: (err) => { /* retry button */ },
  });

  return (
    <ChatLayout>
      <div className="flex-1 overflow-auto">
        {messages.map((m) => (
          <MessageBubble key={m.id} role={m.role}>
            {m.parts.map((part, i) => {
              if (part.type === "text") return <Markdown key={i}>{part.text}</Markdown>;
              if (part.type === "tool-call") return <ToolCallCard key={i} {...part} />;
              if (part.type === "provider") return <ProviderChip key={i} name={part.name} latency={part.ms} />;
            })}
          </MessageBubble>
        ))}
      </div>
      <MessageInput
        value={input} onChange={handleInputChange} onSubmit={handleSubmit}
        loading={isLoading} onStop={stop} onError={error ? reload : undefined}
      />
    </ChatLayout>
  );
}
```

**Markdown setup (`components/chat/Markdown.tsx`):**

```tsx
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";
import rehypeHighlight from "rehype-highlight";
import "katex/dist/katex.min.css";
import "highlight.js/styles/github-dark.css";

export function Markdown({ children }: { children: string }) {
  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm, remarkMath]}
      rehypePlugins={[rehypeHighlight, rehypeKatex]}
      components={{
        code: ({ inline, className, children, ...props }) => {
          if (inline) return <code className="bg-muted px-1 rounded">{children}</code>;
          return (
            <div className="relative my-2">
              <button className="absolute top-2 right-2 text-xs">Copy</button>
              <pre className="p-4 bg-bg-2 rounded overflow-x-auto"><code className={className}>{children}</code></pre>
            </div>
          );
        },
      }}
    >
      {children}
    </ReactMarkdown>
  );
}
```

**Slash command palette (`components/chat/SlashCommandPalette.tsx`):**

```tsx
import { Command } from "cmdk";

const COMMANDS = [
  { id: "rag", label: "/rag", desc: "RAG bilgi tabanı sorgusu" },
  { id: "workflow", label: "/workflow", desc: "İş akışı oluştur ve çalıştır" },
  { id: "code", label: "/code", desc: "Kod üret (qual_code pipeline)" },
  { id: "translate", label: "/translate", desc: "Çeviri (qual_translate)" },
  { id: "analyze", label: "/analyze", desc: "Derin analiz (qual_analysis)" },
  { id: "tts", label: "/tts", desc: "Metni sese dönüştür (Piper)" },
  { id: "transcribe", label: "/transcribe", desc: "Audio transkript (WhisperX)" },
];

// Triggered when user types "/" at input start
```

---

### Phase N — MCP Server JSON-RPC Implementation

**ABS as MCP Server (FastAPI):**

```python
# core/backend/app/api/mcp_server.py
from fastapi import APIRouter, Depends, Header, HTTPException
from typing import Optional

router = APIRouter(prefix="/mcp")

@router.post("")
async def mcp_endpoint(
    request: dict,  # JSON-RPC 2.0
    authorization: Optional[str] = Header(None),
):
    # Auth: Bearer token validation
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing_bearer_token")
    token = authorization[7:]
    tenant = await validate_mcp_token(token)
    if not tenant:
        raise HTTPException(401, "invalid_token")

    # JSON-RPC dispatch
    method = request.get("method")
    request_id = request.get("id")

    if method == "tools/list":
        tools = await list_abs_tools(tenant)  # 122 tool spec
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "tools": [
                    {
                        "name": t["name"],
                        "title": t.get("title", t["name"]),
                        "description": t["description"],
                        "inputSchema": t["input_schema"],
                        "outputSchema": t.get("output_schema"),
                    }
                    for t in tools
                ],
            },
        }

    elif method == "tools/call":
        params = request.get("params", {})
        tool_name = params["name"]
        args = params.get("arguments", {})
        try:
            result = await invoke_abs_tool(tool_name, args, tenant=tenant)
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "content": [{"type": "text", "text": result}],
                    "isError": False,
                },
            }
        except ToolNotFoundError as e:
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32602, "message": f"Unknown tool: {tool_name}"},
            }
        except Exception as e:
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "content": [{"type": "text", "text": str(e)}],
                    "isError": True,
                },
            }

    elif method == "resources/list":
        resources = await list_rag_documents(tenant)
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "resources": [
                    {"uri": f"abs://rag/{tenant}/{r['id']}", "name": r["title"], "mimeType": "text/markdown"}
                    for r in resources
                ],
            },
        }

    elif method == "prompts/list":
        # Slash commands as MCP prompts
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "result": {
                "prompts": [
                    {"name": "rag", "description": "Query ABS knowledge base", "arguments": [{"name": "query", "required": True}]},
                    {"name": "workflow", "description": "Synthesize and execute workflow", "arguments": [{"name": "intent", "required": True}]},
                ],
            },
        }

    else:
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32601, "message": f"Method not found: {method}"},
        }
```

**Müşteri kurulum:**

```bash
# 1. ABS panel'de Settings → MCP Tokens → "Generate token"
# Output: abs_mcp_token_xxxxx

# 2. Müşteri Claude Code CLI:
claude mcp add --transport http abs https://customer-server.com:8000/mcp \
  --header "Authorization: Bearer abs_mcp_token_xxxxx"

# 3. Veya .mcp.json (proje-bazlı):
cat > .mcp.json <<'EOF'
{
  "mcpServers": {
    "abs": {
      "type": "http",
      "url": "${ABS_BASE_URL}/mcp",
      "headers": {"Authorization": "Bearer ${ABS_MCP_TOKEN}"}
    }
  }
}
EOF
```

**Müşteri kullanım (Claude Code'da):**

```
> /mcp__abs__rag müşteri sorularını özetle

# Veya tool call dolaylı:
> Bana son 10 müşteri sorusunu özetle, ABS RAG'den çek
[Claude → MCP tools/list → görür "rag_query" → tools/call → result]
```

---

### Phase P — Claude Code Hooks Integration (YENİ — 6h)

### Hedef
Müşteri Claude Code kullanırken ABS backend'iyle hook'lar üzerinden konuşur:
- **PreToolUse** → ABS'ten quota/permission check (engelle veya devam)
- **PostToolUse** → ABS audit log'a yaz
- **UserPromptSubmit** → token budget kontrolü
- **SessionStart** → ABS'e tenant identification

### Deliverables

**1. Backend hook receiver endpoint'leri:**

```python
# core/backend/app/api/claude_code_hooks.py
@router.post("/v1/hooks/quota-check")  # PreToolUse
async def quota_check(body: dict, auth = Depends(verify_hook_token)):
    """Claude Code PreToolUse → ABS budget check.
    Body: {tool_name, tool_input, session_id, ...}
    Response: {decision: allow|block, reason: ...}
    """
    tenant = auth.tenant_slug
    quota = await get_remaining_quota(tenant)
    if quota.remaining_tokens < estimated_tokens(body):
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"ABS quota exhausted ({quota.percent_used}%). Wait for Çar reset.",
            }
        }
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}

@router.post("/v1/hooks/audit-log")  # PostToolUse
async def audit_log(body: dict, auth = Depends(verify_hook_token)):
    """Claude Code PostToolUse → ABS audit log write."""
    await db.audit_log.insert({
        "tenant": auth.tenant_slug,
        "actor": body.get("user_email"),
        "tool_name": body.get("tool_name"),
        "tool_input": body.get("tool_input"),
        "result": body.get("tool_response"),
        "ts": datetime.now(timezone.utc),
        "source": "claude_code_hook",
    })
    return {"ok": True}

@router.post("/v1/hooks/session-start")  # SessionStart
async def session_start(body: dict, auth = Depends(verify_hook_token)):
    """Claude Code SessionStart → ABS tenant identification."""
    return {
        "additionalContext": f"You are working in ABS tenant '{auth.tenant_slug}'. "
                             f"122 MCP tools available. Use /mcp__abs__rag, /mcp__abs__workflow.",
    }
```

**2. Hook config (`docs/CLAUDE_CODE_HOOKS_SETUP.md`):**

```json
// ~/.claude/settings.json (müşteri makinesinde)
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Edit|Write|mcp__abs__.*",
        "hooks": [
          {
            "type": "http",
            "url": "${ABS_BASE_URL}/v1/hooks/quota-check",
            "timeout": 5,
            "headers": {"Authorization": "Bearer ${ABS_HOOK_TOKEN}"},
            "allowedEnvVars": ["ABS_HOOK_TOKEN", "ABS_BASE_URL"]
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "http",
            "url": "${ABS_BASE_URL}/v1/hooks/audit-log",
            "timeout": 5,
            "headers": {"Authorization": "Bearer ${ABS_HOOK_TOKEN}"}
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "http",
            "url": "${ABS_BASE_URL}/v1/hooks/session-start",
            "timeout": 5,
            "headers": {"Authorization": "Bearer ${ABS_HOOK_TOKEN}"}
          }
        ]
      }
    ]
  }
}
```

**3. ABS panel'de "Hook Token" generate UI** (`/admin/users/[id]/integrations`):
- "Claude Code Hooks" section
- "Generate hook token" button → `abs_hook_token_xxxxx`
- Copy command: `export ABS_BASE_URL=... ABS_HOOK_TOKEN=...`
- Düzenleme rehberi (link to `docs/CLAUDE_CODE_HOOKS_SETUP.md`)

### Use Cases (Customer-Facing)

| Senaryo | Hook | Etki |
|---------|------|------|
| CTO Claude Code'da `Bash(deploy --prod)` çalıştırmak istiyor | PreToolUse | ABS Cerbos check + onay gate |
| Senior dev `Write(secrets.json)` yazmaya çalışıyor | PreToolUse | ABS PII detection + block |
| Tüm Claude Code aktivitesi audit edilsin | PostToolUse | ABS audit log timeline'a düşer |
| Claude Code session başında tenant identifier'ı yüklensin | SessionStart | ABS context injection |
| `mcp__abs__rag` çağrıları rate limit edilsin | PreToolUse | ABS quota gate |

### Test
- ABS panel'den hook token üret
- ~/.claude/settings.json'a inject
- Claude Code'da `bash echo test` çalıştır → ABS audit log'da görünür mü
- ABS quota'yı manuel doldur → Claude Code Bash → "deny" response → blocklandı mı

### Exit Gate
- 3 hook endpoint LIVE (quota-check, audit-log, session-start)
- Claude Code → ABS hook integration test 5/5 PASS
- Token generate UI shipped
- Documentation `docs/CLAUDE_CODE_HOOKS_SETUP.md` ready

---

### Phase Q — Premium Dashboard Patterns (Reference Card)

Phase A-O implementasyonlarında kullanılacak dashboard pattern'leri:

#### Linear (en güçlü referans)
- **Adapt edilen:** Cmd+K command palette (`cmdk`), keyboard shortcuts (`?` for help), real-time updates (WebSocket veya TanStack Query polling), sidebar nav, minimalist tasarım
- **Stack:** React + Next.js + Radix UI + Inter + custom dark mode + Framer Motion + GraphQL/Apollo (biz REST kullanırız)
- **ABS uyarlaması:** Her sayfa Cmd+K'ya açık, slash + arrow key navigation, J/K (next/prev item)

#### Vercel Dashboard
- **Adapt edilen:** OKLCH color system (zaten var), dark/light/system theme (`next-themes`), real-time analytics (Tremor + TanStack Query), card-based layout
- **ABS uyarlaması:** /panel ana sayfa Tremor Card grid'i, real-time cascade call counts, p95 latency cards

#### Supabase Studio
- **Adapt edilen:** Side panel pattern (Sheet for detail), SQL editor (Monaco), TanStack Table grid, purple accent (biz mavi kullanırız)
- **ABS uyarlaması:** Tool browser detail Sheet, Neo4j Cypher editor (Monaco), audit log TanStack Table

#### Datadog
- **Adapt edilen:** Time series charts (Tremor AreaChart + Recharts), modular widget grid (custom react-grid-layout opsiyonel), real-time WebSocket
- **ABS uyarlaması:** /panel/quota saatlik kullanım grafiği, /admin/audit timeline

#### Obsidian Canvas / Graph View
- **Adapt edilen:** Force-directed graph (`react-force-graph-3d`), free-form canvas, real-time linking
- **ABS uyarlaması:** Phase L neural graph (cosmos replace), workflow builder canvas

#### n8n Cloud
- **Adapt edilen:** Node-based editor (`@xyflow/react`), drag-to-connect, zoom/pan/mini-map, execution history
- **ABS uyarlaması:** Phase B workflow-builder

### Genel Tasarım Sistemi (tüm phase'ler)

**Color tokens (OKLCH):**
```css
--abs-bg-base: oklch(15% 0.01 260);          /* dark default */
--abs-bg-surface: oklch(18% 0.01 260);
--abs-bg-elevated: oklch(22% 0.01 260);
--abs-fg-base: oklch(95% 0.01 260);
--abs-fg-muted: oklch(60% 0.01 260);
--abs-brand: oklch(60% 0.18 260);            /* mavi */
--abs-success: oklch(65% 0.18 145);
--abs-warning: oklch(75% 0.18 75);
--abs-danger: oklch(60% 0.22 25);
--abs-border: oklch(30% 0.01 260);
```

**Typography:**
- UI: Inter (300/400/500/600/700)
- Mono (data, code, IDs): JetBrains Mono (400/500/700)
- Display (hero, big metrics): Inter 700 with `letter-spacing: -0.03em`

**Spacing:** 4/8/12/16/24/32/48/64 (Tailwind scale)
**Border:** 1px solid `--abs-border`, 6-8px radius
**Shadow:** subtle `0 1px 3px rgba(0,0,0,0.4)` sadece elevated cards
**Animation:** Framer Motion entrance (fade+slide 8px, 0.2s ease-out), NO parallax/orbit
**Icons:** Lucide React (default) + Phosphor Icons (specific abstract concepts)

---

**Brief enrich edildi v2 — 2026-05-01:** 4 yeni bölüm (Vercel AI SDK detay, MCP JSON-RPC örnekleri, Claude Code Hooks integration, Premium Dashboard reference card). Worker'a tüm teknik detaylar sağlanmış durumda.
