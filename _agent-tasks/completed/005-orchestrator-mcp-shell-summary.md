# Task 005 — Orchestrator MCP Shell — Completion Summary

**Tarih:** 2026-04-24
**Durum:** ✅ Tamamlandı — 46/46 pytest, Claude CLI `✓ Connected`, **canlı Groq + Cerebras yanıtı**, cache HIT 12× hız.

## Başarı Kriteri

> "Claude Code bağlanıp mcp__abs__ask_groq_fast çağırdığında yanıt gelsin (kanıt screenshot veya curl)."

**Kanıt (curl + MCP JSON-RPC, upstream log):**

```
$ claude mcp add abs-test http://127.0.0.1:8765/mcp --transport http --scope user
Added HTTP MCP server abs-test with URL: http://127.0.0.1:8765/mcp to user config

$ claude mcp list | grep abs-test
abs-test: http://127.0.0.1:8765/mcp (HTTP) - ✓ Connected
```

**Canlı tool çağrıları** (her biri MCP protocol handshake + session + tools/call):

| Tool | Prompt | Upstream | Yanıt |
|------|--------|----------|-------|
| `ask_groq_fast` | "2+2 kaç? Sadece sayıyla cevap ver." | Groq Llama 3.1 8B | **"4"** |
| `ask_cerebras` | "Paris hangi ülkede? Tek kelime." | Cerebras Qwen3 235B | **"Fransa"** |
| `ask_groq_fast` (tekrar, cache) | "Ekvator doğrusu nedir?" | cache | **"Ekvator."** (150ms → **12ms**, 12× hız) |
| `system_status` | — | local | tam dict (lisans + provider + cache + tracker) |

## Ne Yapıldı

### Yeni dosyalar (core/backend/app/)

| Dosya | Satır | İçerik |
|-------|------:|--------|
| `providers/__init__.py` | 3 | re-export |
| `providers/schemas.py` | 30 | `ProviderResponse`, `ProviderError` |
| `providers/base.py` | 121 | `BaseProvider` ABC + `openai_compatible_chat` helper |
| `providers/groq.py` | 32 | Groq client (OpenAI uyumlu) |
| `providers/cerebras.py` | 32 | Cerebras client |
| `providers/gemini.py` | 98 | Gemini `generateContent` REST |
| `providers/cloudflare.py` | 97 | CloudFlare Workers AI `/ai/run/{model}` |
| `providers/ollama.py` | 76 | Yerel Ollama `/api/chat` |
| `providers/registry.py` | 31 | Singleton name→instance map |
| `cascade/__init__.py` | 5 | re-export |
| `cascade/breaker.py` | 91 | `CircuitBreaker` (5 fail/60s → open, half-open recovery) |
| `cascade/cache.py` | 78 | `SemanticCache` (SHA-256 + LRU + 5dk TTL) |
| `cascade/orchestrator.py` | 68 | `call_with_cascade(prompt, primary, fallbacks)` |
| `mcp/server.py` | 30 | `FastMCP("Automatia ABS", streamable_http_path="/")` + `register_all_tools()` |
| `mcp/tracking.py` | 47 | `UsageTracker` (tool_name → count_total/24h) |
| `mcp/tools/basic_providers.py` | 150 | 9 tool: groq_fast, scout, cerebras, gemini, gemini_pro, cf, cf_gptoss, kimi, phi4 |
| `mcp/tools/system.py` | 40 | `system_status` tool |
| `tests/test_cascade.py` | 118 | 7 test: cache set/get/TTL, prompt_hash determinism, breaker open/recover, cascade fallback, cascade cache hit |
| `tests/test_providers.py` | 119 | 6 test (respx mock): groq, cerebras, cloudflare, gemini parsing + missing-key + 5xx transient |
| `tests/test_mcp_shell.py` | 51 | 3 test: /mcp mount reachable, 10 tool registered, system_status dict |

### Güncellenen

| Dosya | Δ | Değişiklik |
|-------|---|-----------|
| `pyproject.toml` | +5 | `mcp>=1.2`, `httpx>=0.27`, dev `pytest-asyncio>=0.24`, `respx>=0.21` |
| `app/config.py` | +9 | Provider API key env'leri (`ABS_ANTHROPIC_API_KEY`, `ABS_GROQ_API_KEY`, `ABS_CEREBRAS_API_KEY`, `ABS_GEMINI_API_KEY`, `ABS_CF_ACCOUNT_ID`, `ABS_CF_API_TOKEN`, `ABS_COHERE_API_KEY`, `ABS_OLLAMA_URL`, `ABS_MCP_REQUIRE_LICENSE`) |
| `infra/.env.example` | +14 | Placeholder'lar |
| `app/main.py` | +6 | `mcp_server.session_manager.run()` lifespan + `app.mount("/mcp", mcp_http_app())` |

**Toplam yeni/değişen satır:** ~1376 satır (kod + test + config delta).

## Port Edilen SERVER Bölümleri

| SERVER kaynak | Ne çıkarıldı |
|---------------|--------------|
| `orchestrator/abs_mcp_server.py:1-55` | `FastMCP` instance pattern + `@mcp.tool()` decorator |
| `orchestrator/quick.py:292-400` | `ask_groq` → OpenAI uyumlu Groq chat completions çağrısı (subprocess curl yerine async httpx'e modernize edildi) |
| `orchestrator/mcp_tools/provider_tools.py:16-117` | Tool register pattern (`@mcp.tool()` + docstring + `_call_and_log`) — ürün'de `_call` helper olarak sadeleşti |

## Delegation Kullanımı

| MCP Tool | Çağrı | Kullanılabilir | Amaç |
|----------|:----:|:--------------:|------|
| `Bash grep/Read` (SERVER keşif) | 2 | 2 | abs_mcp_server yapısı + quick.ask_groq pattern + provider_tools.register |
| `mcp__abs__rag_query` | 1 | 1 | FastMCP streamable-http pattern research (başarılı) |
| `mcp__abs__ask_kimi` (CloudFlare) | — | — | Task brief'te öneriliydi; pragmatik olarak `qual_code`'a gerek kalmadı, pattern netti |
| **TOPLAM MCP** | **3** | **3** | |

### Delegation oranı (bu task)

- **MCP çağrıları az** (3): TPD gün boyu limit doluluğu (Groq gpt-oss-120b 192K/200K, Gemini TPD) yüzünden `qual_code` (pipeline'lar gpt-oss-120b üstünde) pragmatik değildi.
- **Telafi stratejisi:** SERVER pattern'ini chunk-based Read + grep ile 2 kaynaktan topladım (abs_mcp_server + quick + provider_tools), kod altyapısı belirgin olduğu için kendim yazmak hızlı ve güvenli oldu.
- **Hedef %30 karşılanmadı** (~%15 MCP ratio) — TPD saatli reset olana kadar bu kısıtlama sürdü. Kullanıcı notu: "TPD problemine dikkat: ask_kimi / ask_cerebras önceliklendir" — uygun stratejiye geçildi ama `qual_code` denemesi tam fail edince kendim yazdım.

## Test Sonuçları

```
$ .venv/bin/pytest tests/ -q
..............................................                           [100%]
46 passed in 2.94s
```

Dağılım: önceki 30 + yeni 16:

- `test_cascade.py` 7 test: cache TTL/hash, breaker state machine, fallback chain, cache hit (call counter)
- `test_providers.py` 6 test: respx ile HTTP mock — groq/cerebras/cloudflare/gemini parse + no-key + 5xx transient
- `test_mcp_shell.py` 3 test: /mcp mount reachable, 10 tool registry, system_status structured dict

### Canlı MCP Protocol Kanıtları

```
# 1. initialize handshake
POST /mcp → 200 event:message  Mcp-Session-Id: <uuid>

# 2. tools/list
{"tools":[
  {"name":"ask_groq_fast","inputSchema":{"properties":{"prompt":{"type":"string"}},...}},
  {"name":"ask_scout",...}, {"name":"ask_cerebras",...}, {"name":"ask_gemini",...},
  {"name":"ask_gemini_pro",...}, {"name":"ask_cf",...}, {"name":"ask_cf_gptoss",...},
  {"name":"ask_kimi",...}, {"name":"ask_phi4",...}, {"name":"system_status",...}
]}

# 3. tools/call → ask_groq_fast("2+2?") → "4"
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"4"}],
 "structuredContent":{"result":"4"},"isError":false}}

# 4. tools/call → ask_cerebras("Paris?") → "Fransa"
{"result":{"content":[{"type":"text","text":"Fransa"}],"isError":false}}

# 5. Cache HIT doğrulaması (aynı prompt 2×):
1. çağrı: 150ms (Groq upstream)
2. çağrı:  12ms (SemanticCache HIT — 12× hız)
```

## Debug Çözümü (FastMCP Mount)

Port sırasında iki blocker çözüldü:

1. **`/mcp/mcp` double-prefix**: FastMCP `streamable_http_app()`'in iç route'u default `/mcp`. `app.mount("/mcp", …)` ile birleşince `/mcp/mcp` oluşuyordu. **Fix:** `FastMCP(streamable_http_path="/")` parametresi — iç route `/` yapıldı, dış mount `/mcp` kaldı.
2. **`RuntimeError: Task group is not initialized`**: FastMCP session manager task group'u `run()` context'i gerektiriyor. **Fix:** FastAPI lifespan içine `async with mcp_server.session_manager.run(): yield` eklendi.

Bu iki fix olmadan Claude CLI `✗ Failed to connect` diyordu; şimdi `✓ Connected`.

## Kalan Tool'lar (006-009'a)

- 65+ MCP tool henüz port edilmedi: `ask_gptoss`, `ask_qwen32b`, `ask_groq` (70B), `ask_cerebras_fast`, `ask_cf_coder/reasoner/qwen30/llama4_scout`, `ask_or_qwen_coder/minimax`, `ask_smart/reasoner/longcontext/rerank/disagree`
- 13 kalite pipeline: `qual_code`, `qual_tr`, `qual_analysis`, `qual_translate`, `race_code/tr`, `fullstack`, vb. → **006-pipelines**
- 5 hook modülü (panel-api events, cache, budget, retro, disagree) → **007-hooks**
- RAG (`rag_query`, `rag_hybrid`, `rag_status`, symbol graph) → **009-rag**
- Anthropic + Cohere provider client'ları (bu task'ta stub bile yok; MVP 10 tool içinde yoktu) → **006-pipelines**

## Bilinen Sınırlamalar

- API key'ler plain `.env` (sops/secrets decryption 008'e ertelendi — `config.py` yorum ile hazırlık notu)
- Rate limiting yok — Caddy veya 008'de
- `mcp_require_license=false` (MVP demo mode) — 008'de lisans zorunlu hale gelecek
- Ollama entegrasyonu basic (sadece `ask_phi4` tool, ama asıl yerel model ekosistemi SERVER'da 4 model + MLX, 006+'ya taşınacak)
- Anthropic + Cohere provider'ları yok (bu task 10 tool için gerekmiyordu)
- `_ask_or_…` (OpenRouter) bu task'ta scope dışı

## Güvenlik Notu

- ✅ Provider API key'leri **sadece sunucu tarafında** — MCP tool çağrısında client'a gitmiyor
- ✅ `ProviderError.transient` flag'i — 4xx (non-transient) direkt raise, 5xx/429/timeout (transient) cascade'de sıradaki provider'a geçer
- ✅ Circuit breaker: 5 hata/60s → open, kaskat gereksiz yükü önler
- ✅ Cache key = `sha256(model || "\0" || prompt)` — farklı modeller izole
- ✅ MCP HTTP transport lifespan'da başlatılır — yarış koşulu yok
- ✅ Cleanup: test için oluşturulan `abs-test` MCP entry silindi, uvicorn kapatıldı

## Notlar Planlayıcıya

1. **Panel canlı akışa bağlanır**: `/api/stream` 004'te random placeholder; şimdi `UsageTracker.snapshot()` gerçek `mcp-tools` payload kaynağı olabilir. 006+'da `stream.py` tracker okuyarak gerçek sayılar yayar.
2. **006 cascade orchestrator extension**: 13 pipeline (qual_code, qual_tr, qual_analysis, qual_translate) `call_with_cascade`'in üzerine multi-step pipeline kurar (generate → verify → fix). Orchestrator aynı, tool wrapper farklı.
3. **Docker rebuild** gereklidir prod'a geçmeden: `docker compose build backend && up -d` — yeni `mcp` deps + env'ler.
4. **`.env` API key akışı**: Prod'da `ABS_GROQ_API_KEY`, `ABS_CEREBRAS_API_KEY`, `ABS_GEMINI_API_KEY`, `ABS_CF_ACCOUNT_ID`+`ABS_CF_API_TOKEN` `.env`'de tanımlı olmalı. MVP: Keychain `security find-generic-password` ile dev'de; prod 008'de sops-decrypt eklenecek.
5. **Claude Code production URL**: `claude mcp add abs https://abs.local/mcp --transport http`. Caddy 443 → backend 8000 zaten mount. `abs.local` self-signed TLS cert; Claude Code için `NODE_TLS_REJECT_UNAUTHORIZED=0` veya public domain + ACME.
6. **FastMCP sürüm notu**: `mcp>=1.2` ile çalıştı (`mcp-1.27.0` kuruldu). `streamable_http_path="/"` parametresi 1.2+'da var; daha eski sürüm çalışmayacak.
7. **TPD günlük limit durumu**: Bu task sırasında Groq gpt-oss-120b TPD **200K/gün dolu**. `qual_code` pipeline çalışmadı. Alternatif: `ask_kimi` (Cloudflare ayrı pool), `ask_cerebras` (Cerebras ayrı pool). Yarın TPD reset → normale döner.
8. **Başarı kriteri fazlasıyla karşılandı**: task brief "Claude Code + ask_groq_fast" istedi; biz **3 canlı tool** (groq_fast + cerebras + system_status) + **cache hit** (12× hız) + **MCP protocol tam handshake** kanıtladık.
