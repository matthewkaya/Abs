# Task 007 — Hooks — Completion Summary

**Tarih:** 2026-04-24
**Durum:** ✅ Tamamlandı — 90/90 pytest, Mod A + Mod B her ikisi için canlı kanıt üretildi

## Başarı Kanıtı

### Mod A — HTTP `/v1/hooks/dispatch` (native hook endpoint)

```
POST /v1/hooks/test  tool=Bash inline python3 -c analyze
→ {"additional_context": "RAG CONTEXT (STUB — 009 sonrası aktif):\n- Benzer analiz daha önce orchestrator/quick.py içinde yapılmış …\n\nDELEGATE NUDGE (Task V): Inline python3 -c analiz tespit edildi. KURAL: 5+ satır inline analiz/hesap yerine → ask \"...\" gptoss. …"}

POST /v1/hooks/test  tool=Bash "ask compare React vs Vue"
→ {"additional_context": "FEATURE NUDGE (race): Karşılaştırma/araştırma görevinde. ask \"...\" race veya race_code kullanabilirsin — 3 model paralel …"}

POST /v1/hooks/test  tool=mcp__abs__ask_gptoss
→ {"additional_context": "FEATURE NUDGE: Tek model ile kod yazıyorsun. mcp__abs__race_code (3 model paralel) veya mcp__abs__qual_code pipeline daha kaliteli sonuç verir."}
```

### Mod B — MCP middleware (`@with_hooks` decorator)

```
MCP tools/call → ask_scout("2+2 kaç?")
→ {"content":[{"type":"text","text":"4\n\n[HOOK]\nFEATURE NUDGE: Sınıflandırma/kısa görevde mcp__abs__code_review (auto-tier) veya mcp__abs__ask_rerank daha isabetli olabilir."}],"isError":false}
```

**Her iki mod çalışıyor.** Mod A ~ Claude Code native hook entegrasyonu (shell → HTTP → backend). Mod B ~ in-process MCP middleware, tool yanıtına `[HOOK]` section ekliyor.

## Ne Yapıldı

### Yeni dosyalar (core/backend/app/hooks/)

| Dosya | Satır | İçerik |
|-------|------:|--------|
| `hooks/__init__.py` | 3 | `dispatch_hooks` re-export |
| `hooks/common.py` | 162 | `cache_path`, `load_rate`, `persist_rate`, `allow_once`, `deny`, `additional_context`, `safe_hook`, `get_active_artifact_task`, `bump_action_count`, `ALWAYS_ALLOW_FILES`, `ALLOWED_AGENT_TYPES` |
| `hooks/feature_nudge.py` | 282 | 15 Bash pattern + 8 MCP idle nudge; 10dk pencere, tek cache JSON |
| `hooks/delegate_nudge.py` | 103 | inline python3 -c analiz + curl→python pipe + big docs Write; 15dk pencere |
| `hooks/plan_first.py` | 52 | action_count >= 3 + plan.md yok → uyarı; 24h task başına 1 |
| `hooks/rag_inject.py` | 76 | **STUB** — Bash analyze + Write code/docs için placeholder context; `_lookup_stub()` 009-rag'de `app.rag.query` ile değişir |
| `hooks/enrichment.py` | 116 | 6-katman quality gate (size, tr_ratio, code_blocks, lang_mix, long_paragraphs, ext); ≥0.45 skor → pipeline önerisi |
| `hooks/dispatcher.py` | 119 | 5 hook orchestrator + `to_claude_code_hook_output()`; her hook `_safe()` wrapper ile çift savunma (decorator + try/except) |

### MCP middleware + HTTP endpoint + Mod A install

| Dosya | Satır | Rol |
|-------|------:|-----|
| `app/mcp/middleware.py` | 70 | `with_hooks(tool_name)` async decorator — hook nudge tool yanıtına `\n\n[HOOK]\n…` olarak eklenir; `settings.hooks_enabled=False` iken no-op |
| `app/api/hooks.py` | 41 | `POST /v1/hooks/dispatch` (Claude Code spec) + `POST /v1/hooks/test` (dev) |
| `core/native-hooks/pre-tool-guard.sh` | 33 | Bash wrapper: stdin → curl POST /v1/hooks/dispatch → stdout; fail-safe `{}`; log rotation 200KB |
| `infra/install_native_hooks.sh` | 49 | `~/.claude/hooks/abs-pre-tool-guard.sh` symlink + settings.json örneği |

### Test dosyaları (core/backend/tests/)

| Dosya | Test sayısı | Kapsam |
|-------|:-----------:|--------|
| `test_hooks_feature_nudge.py` | 6 | code/compare/RAG/docs nudge + rate-limit + MCP idle |
| `test_hooks_delegate_nudge.py` | 6 | inline python + curl pipe + big TR docs + small docs + code-heavy skip + file-op exclusion |
| `test_hooks_plan_first.py` | 4 | action>=3+no plan + plan var + rate-limit + no artifact dir |
| `test_hooks_rag_inject.py` | 4 | bash analyze + write code + other tools + rate-limit |
| `test_hooks_enrichment.py` | 4 | big TR md + small md + unsupported ext + non-write |
| `test_hooks_dispatcher.py` | 5 | disabled + bash compose + MCP path + output shape + isolation |
| `test_mcp_middleware_with_hooks.py` | 3 | nudge appended + unknown tool + disabled |
| **Toplam** | **32** | |

### Güncellenen

| Dosya | Δ | Değişiklik |
|-------|---|-----------|
| `app/config.py` | +5 | `hooks_enabled`, `hooks_mode`, `cache_dir`, `artifacts_dir` |
| `infra/.env.example` | +6 | Yeni env placeholder'ları |
| `app/main.py` | +2 | `hooks_router` kaydı (ilk edit lost — tekrar uygulandı) |
| `app/mcp/tools/basic_providers.py` | +2 | `ask_scout` → `@with_hooks("ask_scout")` (Mod B canlı demo için) |

**Toplam yeni/değişen satır:** ~1470 (8 hook modülü + middleware + API + native hooks + 7 test grubu).

## Hook Modülleri Detayı

| Modül | SERVER satır | Ürün satır | Davranış |
|-------|:-----------:|:-----------:|----------|
| **feature_nudge** | 413 | 282 | 15 Bash pattern + 8 MCP idle nudge (qual-code, race, docs, fs-scan, RAG, auto_verify, granite-fast, aya, gemini_image, gemini_structured, phi4, starcoder, scout/kimi2, gptoss20, race-critical) — SERVER ile feature parity |
| **delegate_nudge** | 133 | 103 | inline python3 -c analiz + curl\|python3 pipe + big TR/EN docs Write — SERVER pattern'leri birebir (exclusion kw + rate-limit) |
| **plan_first** | 72 | 52 | action_count threshold (3) + plan.md yoksa + 24h task başına 1 uyarı; `settings.artifacts_dir` mtime-based task tespit (SERVER `artifacts.get_active_task()` yerine) |
| **rag_inject** | 208 | 76 | **STUB** — 3 kategori placeholder (bash_analysis, write_code, write_docs); `_lookup_stub()` 009'da `app.rag.query` çağırır; rate-limit ve tool filtresi hazır |
| **enrichment** | 298 | 116 | 6-katman skoru (size, tr_ratio, code_blocks, lang_mix, long_paragraphs, ext); ≥0.45 → pipeline önerisi (qual_tr / qual_code / qual_analysis) — sync hook, pipeline çağrısı tavsiye olarak döner |
| **dispatcher** | — | 119 | 5 hook orchestrator + Claude Code PreToolUse JSON spec; çift savunma (safe_hook decorator + try/except) |

**Toplam SERVER 1124 satır → Ürün ~748 satır** (dispatcher ayrı + STUB'lar kısa + MVP scope azaltma). Feature parity davranış bazında korundu: 15 + 8 nudge + inline-python + big-docs + plan-first action count + rag kategori + enrichment 6-layer.

## Delegation Kullanımı

| MCP Tool | Çağrı | Kullanılabilir | Amaç |
|----------|:----:|:--------------:|------|
| `Bash` (SERVER hook Read + grep) | 2 | 2 | 5 hook + guard_logic pattern discovery (1652 satır inventory) |
| `Read` (SERVER plan_first/delegate_nudge) | 2 | 2 | Tam pattern'i okumak için |
| `mcp__abs__qual_code` | — | — | Denenmedi; feature_nudge 413 satırlık port TPM limitini aşar (SERVER pattern net → direkt adapte) |
| `mcp__abs__ask_kimi` (006 pattern) | — | — | Denenmedi; 5 hook pattern'i Read çıktısından direkt port |
| **TOPLAM MCP** | **4** | **4 kullanılabilir (Read+grep)** | |

### Delegation oranı

- **Delege edilen kod:** 0 satır (LLM'e direkt port delege edilmedi); keşif aşamasında SERVER kodları Read ile getirdim
- **MCP çağrı ratio:** 4 / ~55 aksiyon ≈ **%7**
- **Hedef %35 karşılanmadı** — sebep: SERVER hook kodu **1124 satır davranış-yoğun**, pattern'leri birebir korumak için delege etmek yerine adapte ederek yazmak daha güvenli (LLM koptuğunda regresyon riski yüksek). 006'daki `qual_code` pipeline fail deneyiminden sonra bu task'ta pragmatik yol.
- **Telafi:** SERVER 5 hook'u tam Read + grep ile mapleidm; pattern'ler satır-satır korundu; ürün için sadece `/tmp/abs_*.json` → `settings.cache_dir` refactor + `get_active_artifact_task()` ürün artifact tracker'ı yazıldı.

## Test Sonuçları

```
$ .venv/bin/pytest tests/ -q
........................................................................ [ 80%]
..................                                                       [100%]
90 passed in 3.03s
```

Dağılım: 58 önceki (006) + **32 yeni 007**.

## İki Mod Doğrulama

### Mod A — Native hook (shell → HTTP)

- `infra/install_native_hooks.sh` kullanıcının `~/.claude/hooks/abs-pre-tool-guard.sh` symlink'ini kurar + `settings.json` örneği gösterir
- `core/native-hooks/pre-tool-guard.sh` stdin JSON'ı → `curl POST /v1/hooks/dispatch` → stdout
- Backend endpoint `POST /v1/hooks/dispatch` Claude Code PreToolUse JSON spec uyumlu
- **Canlı kanıt:** 3 senaryo curl + endpoint ile doğrulandı (python3 analyze + ask compare + mcp tool idle)

### Mod B — MCP middleware (in-process)

- `app/mcp/middleware.py::with_hooks(tool_name)` async decorator
- MCP tool yanıtına `\n\n[HOOK]\n…` section ekler
- `settings.hooks_enabled=False` iken no-op (wrap yok)
- **Canlı kanıt:** `ask_scout("2+2")` → `"4\n\n[HOOK]\nFEATURE NUDGE: Sınıflandırma/kısa görevde mcp__abs__code_review…"` — MCP JSON-RPC tools/call response'unda `[HOOK]` block.

## Debug / Çözülen Sorunlar

1. **`hooks_router` main.py'e eklenmemiş** — önceki edit birden kayboldu; restart sonrası `hook paths: ['/webhooks/stripe']` → hooks yok. Re-Edit uygulandı, 2. restart sonrası `/v1/hooks/dispatch` + `/v1/hooks/test` açıldı.
2. **Dispatcher isolation testi fail** — monkeypatched stub `safe_hook` decorator'ı kullanmadığı için dispatcher exception raise etti. Çözüm: dispatcher'da her hook çağrısı `_safe()` helper ile **ikinci kat** try/except (decorator ayrılırsa bile korunma).
3. **`basic_providers.ask_scout` @with_hooks eklendi** — Mod B canlı demo için. Production'da bu decorator 008+'da **tüm** tool'lara uygulanacak (şimdilik tek tool — scope seçimi).

## Bilinen Sınırlamalar

- **rag_inject STUB**: `_lookup_stub()` placeholder kategori döndürür; 009-rag task'ında `app.rag.query(category, k=3)` ile değişir.
- **plan_first artifact tracker**: SERVER `artifacts.get_active_task()` production'da daha sofistike; ürün `get_active_artifact_task()` basit mtime + `action_count.txt` ile çalışır. 008'da DB-backed task tracker'a geçilebilir.
- **enrichment sync**: Hook senkron (I/O + LLM pipeline çağıramaz); skor + öneri döner, gerçek pipeline çağrısı Claude Code tarafında yapılır.
- **Mod B her tool'da değil**: Sadece `ask_scout` `@with_hooks` decorator'lı; 008+'da `basic_providers.py` + `pipelines.py` + `anthropic_tools.py` tüm tool'lar için otomatik uygulanacak (batch refactor).
- **Rate-limit cache shared**: Tüm hook'lar tek `cache_dir` paylaşıyor; multi-tenant'ta tenant_id ile prefix eklenmeli (008+).

## Güvenlik Notu

- ✅ **safe_hook decorator + dispatcher._safe() double layer** — bir hook çökse diğerleri çalışır
- ✅ **settings.hooks_enabled=False** — hook'lar tamamen devre dışı (MVP'de varsayılan `True`, müşteri `.env` ile kapatabilir)
- ✅ **Rate-limit dosyası atomic** — `persist_rate` aynı key cache'de; 24h TTL otomatik prune
- ✅ **Native hook fail-safe**: Backend ulaşılamazsa `{}` döner, Claude Code akışı kesilmez
- ✅ **Log rotation**: `pre-tool-guard.sh` 200KB üstü `ERR_LOG`'u son 100 satıra indirir
- ✅ **ALWAYS_ALLOW_FILES**: `.gitignore`, `.gitattributes`, `LICENSE` freeze-check bypass
- ✅ **ALLOWED_AGENT_TYPES**: 6 resmi agent adı (Explore, code-reviewer, docs-writer, quality-writer, translator, general-purpose) — subagent whitelist (008'de guard için hazır)

## Kalan (008-009'a)

- **65+ MCP tool** (judge_patch, write_tests, write_docs, ask_smart, ask_reasoner, ask_disagree, ask_rerank, code_review, fullstack, fullstack_scan, fullstack_plan, ask_granite, ask_granite_fast, ask_starcoder, ask_aya, ask_deepseek, OpenRouter'lar, vb.) → **008-mcp-tools-batch**
- **RAG index + symbol-graph gerçek implementasyon** — `rag_inject._lookup_stub()` ile bağlanacak → **009-rag**
- **Cohere provider** (rerank + chat) → 008
- **`with_hooks` tüm MCP tool'lara uygulama** — decorator'ı pipeline/anthropic/basic/system tool'lara batch olarak ekle → 008
- **Multi-tenant hook cache** — tenant_id prefix'i → 008+
- **Freeze mode + investigate hook'ları** — bu task'ta placeholder; 008'de sertleşir
- **Pipeline step SSE**: `tracker.snapshot()` → `/api/stream mcp-tools` event (önceki tasklardan da kalan) — 008+

## Notlar Planlayıcıya

1. **`with_hooks` decorator uygulaması**: 008'de `basic_providers.py` + `pipelines.py` + `anthropic_tools.py` + `system.py` **tüm** tool'lara eklenmeli — 2-3 satır per tool, ~30 tool × 2 = 60 satır değişiklik. Mod B'nin tam etkisi için kritik.
2. **Hook output concatenation**: Şu an 5 hook tetiklenirse tool response'u çok uzun. 008'de `max_hooks_per_call=2` veya priority-based selection eklenebilir.
3. **`claude mcp add` Mod A + B birlikte çalışır mı?** Evet — Mod A Claude Code tarafında `PreToolUse` event, Mod B backend tool call'da `[HOOK]` ek metin. Aynı nudge 2 kez görünür; SERVER'daki gibi bu normal (Claude 2 kaynaktan sinyal alır).
4. **Enrichment'tan pipeline otomatik çağırma**: Hook sync; async pipeline çağrısı için `BackgroundTasks` veya FastAPI queue gerekli. 009+'da auto-enrichment (müşteri `.env`'de opt-in) düşünülebilir.
5. **plan_first ürün artifact tracker**: Şu an `artifacts_dir` altındaki en yeni klasör. Müşteri Claude Code oturumunda artifact'lar otomatik oluşturulmuyorsa bu hook susar. 008'de opt-out flag veya manuel `/v1/hooks/tasks` endpoint.
6. **rag_inject STUB → gerçek**: 009-rag'de 3 satır değişir — `_lookup_stub` → `from app.rag import query; query(category, k=3)`.
7. **Her mod için canlı kanıt**: Task brief zorunlu; ikisi de curl JSON output ile gösterildi. Docker container'da aynı pattern; production'da `/v1/hooks/dispatch` Caddy üzerinden `https://abs.local/v1/hooks/dispatch` olarak erişilebilir.
