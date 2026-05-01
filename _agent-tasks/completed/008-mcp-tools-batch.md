# Task 008 — Kalan MCP Tool Batch Port (65+ Tool)

## Bağlam

Mevcut: **26 tool** (10 basic + 13 pipeline + 3 Anthropic). SERVER'da **75+ tool** var. Bu task **kalan ~50+ tool**'u kategori bazlı batch'lerde port eder.

**Bağlı docs:**
- `docs/architecture.md` § 2 (75 MCP tool feature parity)
- `docs/research/competitive-analysis.md` § 4 madde 3 ("75 MCP tool — hazır kurulu")
- `_agent-tasks/README.md` Feature Parity Kuralı (eksiltme yasak)

## Kategoriler ve Batch Listesi

### Batch A — Quality + Judge (10 tool)
1. `judge_patch` — AST + LLM 0-10 skor (senior_judge port)
2. `write_tests` — CodeLlama unit test üretici
3. `write_docs` — Qwen3 dokümantasyon üretici
4. `code_review` — Multi-tier (auto/quick/standard/exhaustive)
5. `ask_disagree` — N-model cosine similarity
6. `score_patch_quality` — minimalism + hunk konsantrasyonu (patch_engine.score)
7. `qual_human` — humanize chain
8. `qual_code_human` — humanize + kod
9. `humanize_score` — AI-detect skor
10. `auto_verify_code` + `auto_verify_turkish` (2 tool — 006'dan placeholder vardı, gerçek implementasyon)

### Batch B — Provider Extras (15 tool)
11. `ask_smart` — Auto routing (cache + cost-aware)
12. `ask_rerank` — Cohere rerank primary, LLM fallback
13. `ask_aya` — Cohere Aya 8B (TR gramer)
14. `ask_granite` — IBM Granite (low hallucination)
15. `ask_granite_fast` — Granite 2B (mikro doğrulayıcı)
16. `ask_starcoder` — StarCoder2 3B (FIM)
17. `ask_deepseek` — DeepSeek Coder
18. `ask_codellama` — CodeLlama 7B
19. `ask_phi4` — Phi-4 14B (reasoning)
20. `ask_gemma2` — Gemma 2 9B (factual)
21. `ask_llava` — Llava 7B (görsel)
22. `ask_longcontext` — long context (262K+)
23. `ask_or_qwen_coder` — OpenRouter Qwen Coder
24. `ask_or_minimax` — OpenRouter MiniMax
25. `ask_vllm` — vLLM cluster (advanced)

### Batch C — Gemini Extras (10 tool)
26. `gemini_image` — Gemini 2.5 Flash Image
27. `gemini_image_pro` — Nano Banana Pro
28. `gemini_image_edit` — Image editing
29. `gemini_video` — Gemini video generation
30. `gemini_video_status` — video job status
31. `gemini_video_wait` — video job polling
32. `gemini_lite` — Gemini Flash Lite (hızlı/ucuz)
33. `gemini_url` — URL içerik okuma
34. `gemini_search` — Google Search grounded
35. `gemini_structured` — JSON schema-guaranteed output

### Batch D — Cohere Family (3 tool)
36. `ask_cohere_command_r` — Command R+ chat
37. `ask_cohere_aya` — Aya Expanse
38. `ask_cohere_embed` — Embedding (4096-dim)

### Batch E — System + Cache + Quota (5 tool)
39. `cache_stats` — semantic cache durumu
40. `quota_status` — provider kota durumu (panel widget bağlantısı)
41. `model_health` — health scorer
42. `code_fingerprint` — kod fingerprint hesapla
43. `preview_patch` + `apply_patch` (2 tool — patch_engine wrapper)

### Batch F — Fullstack + Completion (4 tool)
44. `fullstack` — katman-özel kod üretici (auto layer detect)
45. `fullstack_plan` — proje planı
46. `fullstack_scan` — proje tarama
47. `fullstack_detect` — katman tespit

### Batch G — Hook Companions (2 tool)
48. `freeze` — freeze-dir aktive
49. `investigate` — root cause analysis trigger

### Batch H — Workflow + Cohere Alert (2 tool — 009'a yarım kalır)
50. `workflow_status` — workflow_state durumu
51. `ask_cohere_alert_status` — Cohere kullanım

**Toplam: 51 tool** (kalan ~14 tool 009-judge-rag-workflow'da gelir — judge altyapısı + RAG + workflow durability)

## Kaynaklar

```
SERVER /orchestrator/abs_mcp_server.py (1372 satır) — chunk read 8 batch
SERVER /orchestrator/quick.py (2505 satır) — provider call functions
SERVER /orchestrator/mcp_tools/quality_tools.py (135 satır)
SERVER /orchestrator/mcp_tools/provider_tools.py (~400 satır tahmin)
SERVER /orchestrator/mcp_tools/system_tools.py
SERVER /orchestrator/senior_judge.py (judge_patch için)
SERVER /orchestrator/disagreement.py (ask_disagree için)
SERVER /orchestrator/patch_engine.py (apply_patch + preview_patch + score_patch_quality)
SERVER /orchestrator/health_scorer.py (model_health)
SERVER /orchestrator/humanizer/code_fingerprint.py
```

## Beklenen Çıktı

### 1. Yeni Provider Client'lar

- [ ] `app/providers/cohere.py` — full (Command R+, Aya, Embed, Rerank)
- [ ] `app/providers/openrouter.py` — full (free models + paid passthrough)
- [ ] `app/providers/ollama.py` — extras (phi4, gemma2, codellama, granite, aya, deepseek, starcoder, llava — opsiyonel, OLLAMA_URL varsa)
- [ ] `app/providers/vllm.py` — vLLM cluster (opsiyonel, VLLM_URL varsa)
- [ ] `app/providers/gemini_extras.py` — image, video, search, URL, structured (Gemini SDK extras)

### 2. Tool Wrapper Modülleri

Tool kategori bazlı modüller (her batch ayrı dosya):

- [ ] `app/mcp/tools/quality.py` — Batch A (10 tool)
- [ ] `app/mcp/tools/provider_extras.py` — Batch B (15 tool)
- [ ] `app/mcp/tools/gemini_extras.py` — Batch C (10 tool)
- [ ] `app/mcp/tools/cohere_tools.py` — Batch D (3 tool)
- [ ] `app/mcp/tools/system.py` güncelle — Batch E (5 tool)
- [ ] `app/mcp/tools/fullstack.py` — Batch F (4 tool)
- [ ] `app/mcp/tools/hook_companions.py` — Batch G (2 tool)
- [ ] `app/mcp/tools/workflow_stub.py` — Batch H (2 tool, gerçek 009'da)

### 3. Senior Judge Port (judge_patch için)

- [ ] `app/judge/__init__.py`
- [ ] `app/judge/senior.py` — `judge_diff(diff_text, file_path) -> dict` (AST + LLM ağırlıklı)
- [ ] `app/judge/ast_metrics.py` — Python AST analiz (docstring_ratio, type_hints, avg_func_lines)
- [ ] `app/judge/persona.py` — fingerprint loader (üründe **default persona** — müşteri kendi fingerprint yükleyebilir 009'da)

### 4. Patch Engine Port (apply_patch için)

- [ ] `app/patches/__init__.py`
- [ ] `app/patches/engine.py` — port from SERVER patch_engine.py (validate + dry_run + apply + score)
- [ ] `app/patches/policy.py` — port from SERVER patch_policy.py (mass deletion, danger pattern)

### 5. Disagreement Detector Port

- [ ] `app/disagreement/__init__.py`
- [ ] `app/disagreement/detector.py` — N-model cosine similarity (port from disagreement.py)

### 6. Humanizer Stub

- [ ] `app/humanizer/__init__.py`
- [ ] `app/humanizer/scorer.py` — humanize_score (basic implementation; gerçek humanizer SERVER'da büyük modül, MVP basic)
- [ ] `app/humanizer/transformer.py` — qual_human, qual_code_human chain

### 7. Auto-Verify Real Implementation (006'da placeholder kalmıştı)

- [ ] `app/pipelines/verify/code.py` güncelle — Ollama 3 model paralel
- [ ] `app/pipelines/verify/turkish.py` güncelle — Aya gerçek çağrı

### 8. with_hooks Decorator Yayılımı

- [ ] **Tüm yeni 51 tool'a** `@with_hooks` decorator (007 middleware integration)
- [ ] Mevcut 26 tool kontrol — eksikse ekle

### 9. Test

Batch bazlı testler (her batch için 2-3 test):

- [ ] `tests/test_tools_quality.py` — 5 test (judge, write_tests, code_review, ask_disagree mock, score_patch)
- [ ] `tests/test_tools_provider_extras.py` — 4 test (mock Cohere, OpenRouter, Ollama)
- [ ] `tests/test_tools_gemini_extras.py` — 3 test (mock image, search, structured)
- [ ] `tests/test_judge_senior.py` — 4 test (AST metric, fingerprint distance, LLM call, combined score)
- [ ] `tests/test_patches.py` — 4 test (validate, dry_run, apply, score)
- [ ] `tests/test_tools_count.py` — `assert len(registered_tools) >= 75` (Feature Parity guard)

## Kısıtlar

- ❌ SERVER'a Write/Edit yasak
- ❌ Feature Parity Kuralı — **51 tool eksiltme yasak**
- ❌ Hardcoded model ID'leri (config'ten oku)
- ❌ Cohere/OpenRouter/Ollama key yoksa **silent fail** değil — graceful error mesajı (panel'de görünür)
- ✅ `@with_hooks` zorunlu (tüm yeni tool'lar)
- ✅ Batch batch ilerleme — her batch tamamlandıktan sonra kısa test
- ✅ Anthropic+Cohere kotasına dikkat (007 dersi: kritik path düşük delegation)

## Delegation Yönergesi

**Kritik path uyarısı (007 dersi):** Bu task'ta tool wrapper'lar **basit** (5-15 satır her biri), ama provider client'lar (Cohere full, OpenRouter, vLLM) **kritik path**. Wrapper'ları batch delege ET, provider client'ları daha dikkatli adapte et.

### 1. SERVER tool inventory chunk read

```
Read SERVER/orchestrator/abs_mcp_server.py offset=300 limit=200  # tool register batch 1
Read SERVER/orchestrator/abs_mcp_server.py offset=500 limit=200  # batch 2
Read SERVER/orchestrator/abs_mcp_server.py offset=700 limit=200  # batch 3
Read SERVER/orchestrator/mcp_tools/quality_tools.py
Read SERVER/orchestrator/senior_judge.py
Read SERVER/orchestrator/patch_engine.py offset=0 limit=200
Read SERVER/orchestrator/disagreement.py
```

### 2. Provider client'lar için `qual_code` (kritik path — kısa promptlar)

```
mcp__abs__qual_code
  prompt: "Cohere full Python async client.
  - CohereProvider(BaseProvider)
  - command_r, aya_expanse, embed, rerank
  - cohere SDK kullan (cohere>=5.13)
  - Env: ABS_COHERE_API_KEY
  - 5dk timeout, retry 1x"
```

```
mcp__abs__qual_code
  prompt: "OpenRouter async client.
  - OpenRouterProvider(BaseProvider)
  - Free models pool (DeepSeek R1, Qwen3 Coder, Gemma 3 family)
  - HTTP-Referer + X-Title header (OpenRouter requirement)
  - Env: ABS_OPENROUTER_API_KEY"
```

### 3. Tool wrapper'ları batch batch (`ask_kimi` — basit kod, hızlı)

```
mcp__abs__ask_kimi
  prompt: "Batch A - 10 quality tool wrapper:
  @mcp.tool() @with_hooks async def judge_patch(unified_diff: str, file_path: str = '') -> str:
      result = await judge.judge_diff(unified_diff, file_path)
      return json.dumps(result, ...)
  
  [10 tool için aynı pattern, full code]"
```

(Her batch ayrı çağrı: Batch A, B, C, D, E, F, G, H = 8 ayrı `ask_kimi`)

### 4. Senior judge için `qual_code` (orta complexity)

```
mcp__abs__qual_code
  prompt: "Senior judge port from SERVER/orchestrator/senior_judge.py.
  - judge_diff(diff_text, file_path) -> {combined_score, ast_score, llm_score, teaching}
  - AST metrics: docstring_ratio, type_hints_ratio, avg_func_lines
  - Persona loader (default persona JSON)
  - LLM call via provider registry
  - Combined: %60 AST + %40 LLM"
```

### 5. Patch engine için `qual_code`

```
mcp__abs__qual_code
  prompt: "Patch engine Python.
  - validate(file_path, diff) — file size, AST integrity, freeze-dir
  - dry_run(file_path, diff) — in-memory apply
  - apply(file_path, diff, backup=True) — atomic write + rollback
  - score(diff) — minimalism + hunk konsantrasyonu (0-10)
  Port from SERVER/orchestrator/patch_engine.py."
```

### 6. Test (`qual_code` her batch için kısa)

```
mcp__abs__qual_code
  prompt: "pytest 25 test for batch tool registration:
  - mock provider clients (respx)
  - judge senior AST mock
  - patch engine validate/apply/score
  - tools_count == 75+ guard
  Async pytest, fixtures."
```

### 7. Final review

```
mcp__abs__code_review tier="standard"
mcp__abs__judge_patch
```

### Hedef Delegation

- **Min %30 delegation** (provider client'lar dikkatli ama wrapper'lar batch delege)
- MCP çağrı **min 12 kez** (8 batch + 4 critical)

## Adımlar

1. SERVER tool inventory + provider patterns chunk read
2. Cohere full + OpenRouter client (`qual_code` delege)
3. Ollama extras + vLLM client
4. Gemini extras (image, video, search SDK)
5. Senior judge port (`qual_code` delege)
6. Patch engine port (`qual_code` delege)
7. Disagreement detector port
8. Humanizer stub
9. Tool wrapper'lar batch batch (8 batch × `ask_kimi`)
10. with_hooks decorator yayılımı (tüm 75+ tool)
11. main.py update — register_all_tools güncelle (75+ tool)
12. Test (`qual_code` delege)
13. pytest 90 → 90 + ~25 = 115+ passed
14. Docker rebuild + Claude Code manuel test (5-6 yeni tool sample):
    - `mcp__abs__judge_patch` ile diff skor
    - `mcp__abs__write_docs` ile dokümantasyon üret
    - `mcp__abs__ask_aya` ile TR gramer
    - `mcp__abs__gemini_search` web search
    - `mcp__abs__fullstack` katman tespit
15. `code_review` + `judge_patch`
16. Summary

## Doğrulama

```bash
cd core/backend
.venv/bin/pytest tests/ -q
# Beklenen: 90 + 25 = 115+ passed

# Tool sayısı kontrol
python3 -c "
from app.mcp.tools import register_all_tools
from app.mcp.server import mcp_server
register_all_tools(mcp_server)
print(len(mcp_server.list_tools()))
"
# Beklenen: >= 75

cd ../../infra
docker compose build backend && docker compose up -d

# Claude Code test
claude
> mcp__abs__judge_patch unified_diff="--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new" file_path="test.py"
# Beklenen: combined_score, ast_score, llm_score, teaching dict

> mcp__abs__write_docs module_info="FastAPI auth modülü"
# Beklenen: TR markdown doküman

> mcp__abs__gemini_search prompt="Next.js 15 latest features"
# Beklenen: Web grounded yanıt + kaynaklar

> mcp__abs__fullstack prompt="React form yaz" 
# Beklenen: Auto layer=fe tespit + kaliteli kod
```

## Tamamlama

1. `git diff --stat`
2. `judge_patch` + `code_review` skorları
3. `completed/008-mcp-tools-batch-summary.md`:
   ```markdown
   ## Ne Yapıldı
   - 51 yeni MCP tool (75 → 75+ toplam)
   - 5 yeni provider client (Cohere, OpenRouter, Ollama extras, vLLM, Gemini extras)
   - Senior judge + patch engine + disagreement port
   - Humanizer basic
   - 25+ yeni test (115+ toplam)

   ## Tool Sayısı
   - Önceki: 26
   - Yeni eklenen: 51 (Batch A-H detay)
   - Toplam registered: 75+ (Feature Parity guard testi yeşil)

   ## Provider Client Durumu
   - Cohere: full (Command R+, Aya, Embed, Rerank)
   - OpenRouter: free pool + paid passthrough
   - Ollama extras: 7 model (OLLAMA_URL varsa)
   - vLLM: opsiyonel
   - Gemini extras: image (2), video (3), search, URL, structured

   ## Delegation
   [detay — kritik path AZ, wrapper batch ÇOK]

   ## Claude Code Live Kanıtları
   - judge_patch örnek
   - write_docs TR çıktı örnek
   - gemini_search web grounded örnek
   - fullstack auto layer örnek

   ## STUB / Eksik (009'a)
   - workflow_status — gerçek workflow_state DB 009'da
   - rag_query/rag_status/rag_hybrid — gerçek RAG 009'da
   - ask_smart cache+cost router — daha sonra optimize
   ```
4. Task'ı `completed/`'e taşı
5. "008 tamam" rapor

---

**Tahmini süre:** 5-7 saat (en uzun task — 51 tool + 5 provider + 3 utility port)
**Sonraki task:** `009-judge-workflow-rag.md` — Senior judge canlı eğitim + workflow durability + symbol-aware RAG (gerçek implementasyon)
