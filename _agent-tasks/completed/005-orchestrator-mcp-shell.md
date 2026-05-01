# Task 005 — Orchestrator: MCP Shell + Provider Cascade + İlk 10 Tool

## Bağlam

Panel + auth + licensing + landing tamam. Şimdi **ürünün kalbi**: MCP sunucu. Claude Code müşteri makinesinden `claude mcp add abs https://abs.local/mcp` ile bağlanacak, ABS tool'larını çağıracak.

**Kapsam sınırı (önemli):** Bu task **75 MCP tool'un tamamını** port etmez. **İlk 10 basic provider tool**'u port eder:

1. `ask_groq_fast` (Groq Llama 3.1 8B)
2. `ask_cerebras` (Cerebras Qwen3 235B)
3. `ask_gemini` (Gemini Flash)
4. `ask_gemini_pro` (Gemini Pro)
5. `ask_cf` (CloudFlare Workers AI)
6. `ask_cf_gptoss` (CloudFlare GPT-OSS 120B)
7. `ask_scout` (Llama 4 Scout)
8. `ask_kimi` (Cloudflare Kimi K2.5)
9. `ask_phi4` (PC Ollama fallback — MVP'de opsiyonel)
10. `system_status` (ABS sistem durumu)

**Geri kalan 65 tool 006-009 task'larında port edilir.**

Bu task'ın **başarı kriteri:** Claude Code müşteri makinesinden bağlanıp `mcp__abs__ask_groq_fast` çağırabiliyor → yanıt geliyor.

**Bağlı docs:**
- `docs/architecture.md` § 2-4 (bileşen, endpoint, cascade)
- `docs/operations.md` § 5 (circuit breaker, cache)
- `docs/research/free-tier-limits.md` (provider limitler — gerçek sayılar)
- `docs/design-decisions.md` § 13-21 (teknik kararlar)

**Kaynaklar (SERVER'dan OKU, KOPYALAMA — ADAPT):**
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/abs_mcp_server.py` (**1372 satır** — chunk-based read)
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/quick.py` (**2505 satır** — provider call functions + pipeline shells)
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/mcp_tools/provider_tools.py` (19 tool register pattern)
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/mcp_tools/system_tools.py` (system_status + model_health)
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/config_data.py` (provider configs)

## Giriş (Mevcut Durum — 004 sonrası)

- `core/backend/app/` — FastAPI + auth + licensing + webhook + panel (001-004)
- pytest: 24/24 yeşil
- Docker: backend + caddy çalışıyor

## Beklenen Çıktı

### 1. MCP Server Shell (`core/backend/app/mcp/`)

- [ ] `app/mcp/__init__.py`
- [ ] `app/mcp/server.py` — FastMCP instance + registration
  - `from mcp.server.fastmcp import FastMCP`
  - `mcp = FastMCP("Automatia ABS", version="0.1.0")`
  - `/mcp` endpoint mount (FastAPI router'da)
  - Auth wrapper (lisans key geçerli olmalı — demo mode ise limit uygula)
- [ ] `app/mcp/tracking.py` — Her tool çağrısı log'lanır (`_bump_mcp_tool_usage` SERVER pattern'i)
- [ ] `app/mcp/middleware.py` — MCP request interceptor (rate limit + license check)

### 2. Provider Cascade (`core/backend/app/providers/`)

En kritik modül. 6 provider için birim client'lar.

- [ ] `app/providers/__init__.py`
- [ ] `app/providers/base.py` — Abstract base:
  - `class BaseProvider(ABC)`
  - `async def call(self, prompt: str, model: str, **kwargs) -> ProviderResponse`
  - Timeout, retry, error handling
- [ ] `app/providers/groq.py` — Groq client (OpenAI-compatible API)
- [ ] `app/providers/cerebras.py` — Cerebras client
- [ ] `app/providers/gemini.py` — Gemini client (Google GenAI SDK)
- [ ] `app/providers/cloudflare.py` — CloudFlare Workers AI client
- [ ] `app/providers/anthropic.py` — Anthropic client (SDK)
- [ ] `app/providers/cohere.py` — Cohere (rerank + chat)
- [ ] `app/providers/schemas.py` — `ProviderResponse` (response text, model, elapsed, tokens, cached, error)
- [ ] `app/providers/registry.py` — Provider instance registry (config'ten yükle)

### 3. Circuit Breaker + Semantic Cache (`core/backend/app/cascade/`)

- [ ] `app/cascade/__init__.py`
- [ ] `app/cascade/breaker.py` — Circuit breaker:
  - 5 hata / 1dk → open state
  - 60s reset timeout → half-open → test → recover/reopen
  - In-memory state (SQLite persistence 008'de)
- [ ] `app/cascade/cache.py` — Semantic cache:
  - SHA-256 prompt hash
  - 5dk TTL
  - In-memory LRU (100 entry)
- [ ] `app/cascade/orchestrator.py` — `call_with_cascade(prompt, model_alias, providers=[...])` — fallback chain

### 4. İlk 10 MCP Tool (`core/backend/app/mcp/tools/`)

- [ ] `app/mcp/tools/__init__.py` — `register_tools(mcp)` fonksiyonu (tüm tool'ları FastMCP'ye kayıt eder)
- [ ] `app/mcp/tools/basic_providers.py` — 9 basic tool:
  - `ask_groq_fast(prompt: str) -> str`
  - `ask_cerebras(prompt: str) -> str`
  - `ask_gemini(prompt: str) -> str`
  - `ask_gemini_pro(prompt: str) -> str`
  - `ask_cf(prompt: str) -> str`
  - `ask_cf_gptoss(prompt: str) -> str`
  - `ask_scout(prompt: str) -> str`
  - `ask_kimi(prompt: str) -> str`
  - `ask_phi4(prompt: str) -> str` (Ollama fallback, Ollama yoksa error dön)
- [ ] `app/mcp/tools/system.py` — 1 tool:
  - `system_status() -> dict` — lisans, provider health, cache stats, uptime

### 5. API Key Management

- [ ] `app/config.py` güncelle — yeni env'ler:
  - `ABS_ANTHROPIC_API_KEY`
  - `ABS_GROQ_API_KEY`
  - `ABS_CEREBRAS_API_KEY`
  - `ABS_GEMINI_API_KEY`
  - `ABS_CF_ACCOUNT_ID`, `ABS_CF_API_TOKEN`
  - `ABS_COHERE_API_KEY`
  - `ABS_OLLAMA_URL` (optional)
- [ ] `app/config.py`'de key'ler **sops decrypt** edilecek (ileride — MVP'de plain .env OK, ama hazırlık notu yaz)
- [ ] `infra/.env.example` güncelle

### 6. FastAPI Router Mount

- [ ] `app/main.py` güncelle — `/mcp` router mount (FastMCP'nin HTTP transport'unu kullan)
  - SSE transport veya HTTP JSON-RPC (FastMCP default)
  - Auth dependency: lisans key veya admin session

### 7. Test

- [ ] `tests/test_mcp_shell.py`:
  - `test_mcp_endpoint_reachable()` — `/mcp` GET/POST erişilebilir
  - `test_mcp_requires_license()` — lisans yoksa 401
  - `test_tool_registry_has_10_tools()` — registered tool sayısı kontrolü
- [ ] `tests/test_providers.py`:
  - Her provider için **mock response** test (gerçek API çağırma, respx veya VCR)
  - `test_groq_parses_response()`, `test_gemini_parses_response()` vb.
- [ ] `tests/test_cascade.py`:
  - `test_cache_hit_returns_cached()`
  - `test_circuit_breaker_opens_after_5_errors()`
  - `test_fallback_to_next_provider()`

## Kısıtlar

- ❌ SERVER'a Write/Edit yasak
- ❌ **75 tool port etme** (bu task'ta sadece 10)
- ❌ Judge, workflow, RAG, pipeline (sonraki task'lar)
- ❌ Gerçek API key'leri commit etme (sadece .env.example placeholder)
- ✅ FastMCP Python kütüphanesi (`mcp[server]>=1.0`)
- ✅ Async provider client'lar (`httpx.AsyncClient`)
- ✅ Pydantic v2 schemas
- ✅ pytest + respx (HTTP mock) veya pytest-httpx
- ✅ Provider API key'leri env'den (plain .env MVP, sops sonra)

## Delegation Yönergesi

### 1. SERVER'dan pattern research

```
Read /Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/abs_mcp_server.py offset=0 limit=100
Read /Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/quick.py offset=200 limit=200  # ask_groq pattern
Read /Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/mcp_tools/provider_tools.py
```

```
mcp__abs__rag_query "fastmcp python server tool registration http transport"
mcp__abs__rag_query "async httpx provider client with retry circuit breaker"
```

### 2. Base provider + Groq için `qual_code` (kısa prompt — TPM)

```
mcp__abs__qual_code
  prompt: "Python async provider base class + Groq client.
  - BaseProvider ABC: async def call(prompt, model, **kwargs) -> ProviderResponse
  - GroqProvider(BaseProvider): OpenAI-compatible, httpx.AsyncClient
  - Pydantic v2 ProviderResponse schema
  - Timeout 30s, retry 1x
  - Env: ABS_GROQ_API_KEY"
```

Diğer provider'lar ayrı kısa `qual_code` çağrıları (TPM için batch yapma, TEK provider her çağrıda).

### 3. Circuit breaker + cache için `qual_code`

```
mcp__abs__qual_code
  prompt: "Circuit breaker + semantic cache Python.
  - CircuitBreaker: 5 hata/60s → open, 60s reset, half-open test
  - SemanticCache: SHA-256 hash, 5dk TTL, LRU 100 entry
  - In-memory (asyncio.Lock ile thread-safe)
  - Pytest uyumlu (mock_time)"
```

### 4. MCP tool wrapper için `ask_kimi` (kod üretim ucuz + hızlı)

```
mcp__abs__ask_kimi
  "FastMCP tool wrapper pattern:
  @mcp.tool()
  async def ask_groq_fast(prompt: str) -> str:
      provider = providers.get('groq')
      return await provider.call(prompt, model='llama-3.1-8b-instant')
  
  9 basic tool'u bu pattern'de üret [model listesi]."
```

### 5. Testler için `qual_code`

```
mcp__abs__qual_code
  prompt: "pytest + respx: 3 test grup
  - test_mcp_shell: endpoint reachable, license required
  - test_providers: groq, gemini mock response parsing
  - test_cascade: cache hit, breaker open, fallback
  Mock HTTP response örnekleri dahil."
```

### 6. Final skor

```
mcp__abs__code_review tier="standard"
mcp__abs__judge_patch
```

### Hedef Delegation

- En az **%30 delegation** (büyük task ama yeni kod, research hafif)
- MCP çağrı min **8 kez**
- **TPM UYARISI:** Her `qual_code` promptu **≤ 200 kelime** olsun

## Adımlar (sıra önemli)

1. SERVER `abs_mcp_server.py` ilk 200 satır read → FastMCP pattern öğren
2. SERVER `quick.py` `ask_groq` fonksiyonunu read (satır 200-400 civarı)
3. `rag_query` ile FastMCP best practices
4. pyproject.toml: `mcp[server]>=1.0`, `httpx[http2]>=0.27`, `respx>=0.22` dev dep ekle
5. `app/providers/base.py` + `app/providers/schemas.py` (`qual_code` delege)
6. `app/providers/groq.py` (`qual_code` delege, kısa prompt)
7. Diğer 5 provider (her biri ayrı `qual_code` delege — 6 ayrı çağrı toplam)
8. `app/cascade/breaker.py` + `cache.py` + `orchestrator.py` (`qual_code` delege)
9. `app/mcp/server.py` + `middleware.py` + `tracking.py` (`qual_code` delege)
10. `app/mcp/tools/basic_providers.py` — 9 tool wrapper (`ask_kimi` delege)
11. `app/mcp/tools/system.py` — `system_status` tool
12. `app/main.py` güncelle — MCP router mount
13. `app/config.py` + `.env.example` — provider API keys env'leri
14. Test yazımı (`qual_code` delege)
15. `pytest tests/ -q` → 24 önceki + ~15 yeni = en az 39 passed
16. Docker build + up + Claude Code test (manuel):
    ```bash
    claude mcp add abs https://abs.local/mcp
    # Test prompt'ta: "abs ask_groq_fast ile 2+2 nedir?" → yanıt gelmeli
    ```
17. `code_review` + `judge_patch`
18. Summary

## Doğrulama

```bash
# 1. Install
cd core/backend
.venv/bin/pip install -e ".[dev]"

# 2. Test
.venv/bin/pytest tests/ -q
# Beklenen: en az 39 passed

# 3. Docker build
cd ../../infra
docker compose build backend
docker compose up -d

# 4. MCP endpoint erişim
curl -k https://abs.local/mcp
# Beklenen: MCP protocol handshake response (FastMCP)

# 5. Claude Code bağlantı (manuel)
# Farklı terminal:
claude mcp add abs https://abs.local/mcp
# Claude açılır, tool listesinde mcp__abs__ask_groq_fast, ask_gemini vb. görünür
claude  # başlat
# İçeride prompt: "ask_groq_fast ile 2+2?"
# Beklenen: Groq'tan "4" yanıtı (veya model default response)

# 6. system_status tool test
# Claude'da: "abs system status"
# Beklenen: lisans durumu, 6 provider health, cache stats

# 7. Cache hit test
# Aynı prompt'u 2 kez çağır → ikincisi cache'ten döner (< 100ms)
```

## Tamamlama

1. `git diff --stat` — değişen satır
2. `judge_patch` skor
3. `completed/005-orchestrator-mcp-shell-summary.md`:
   ```markdown
   ## Ne Yapıldı
   - MCP server shell: N dosya, M satır
   - Provider cascade: 6 provider client
   - Circuit breaker + cache
   - 10 basic tool
   - Test: K passed

   ## Port Edilen SERVER Bölümleri
   - abs_mcp_server.py: satır X-Y (FastMCP pattern)
   - quick.py: ask_groq, ask_cerebras, ask_gemini pattern

   ## Delegation Kullanımı
   [detay]

   ## Claude Code Bağlantı Kanıtı
   - Screenshot: claude-mcp-tools.png
   - ask_groq_fast yanıt örneği

   ## Kalan Tool'lar (006-009'a)
   - 65 MCP tool henüz port edilmedi (rag, quality, judge, workflow, fullstack, vs.)
   - 5 hook modülü (007)
   - 13 pipeline (006)

   ## Bilinen Sınırlamalar
   - API key'ler plain .env (sops 008'de)
   - Ollama entegrasyonu basic (ask_phi4 fallback only)
   - Rate limiting yok (008'de)
   ```
4. Task'ı `completed/`'e taşı
5. "005 tamam" rapor

---

**Tahmini süre:** 4-5 saat (yeni kod + provider cascade + test)
**Sonraki task:** `006-pipelines.md` — 13 quality pipeline port (qual-code, qual-tr, qual-analysis, qual-translate + varyantlar)
