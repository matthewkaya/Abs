# Task 006 — Quality Pipelines (13 Pipeline Port)

## Bağlam

005'te MCP shell + 10 basic tool kuruldu. Şimdi **ürünün farklılaştırıcı değeri**: multi-model quality pipeline'lar. Tek LLM çağırmak yerine 3-4 model zincirleyerek **daha yüksek kalite** elde eder — competitive analysis'te "qual-tr benzersiz" dediğimiz feature.

13 pipeline SERVER'dan port edilecek. Her biri `@mcp.tool()` ile expose edilir, Claude Code kullanıcısı `mcp__abs__qual_code`, `mcp__abs__qual_tr` vb. ile çağırır.

**Bağlı docs:**
- `docs/research/competitive-analysis.md` § 4 madde 1 (Türkçe quality pipeline — unique)
- SERVER'daki `/Users/eneseserkan/.claude/CLAUDE.md` § "KALİTE PİPELINE"

## 13 Pipeline (Tam Liste)

### A) Quality (4 pipeline — ana)
1. **qual-code** — Üret(kimi+gpt-oss 20B paralel) → Doğrula(codellama) → Düzelt(gptoss 120B). Kod için.
2. **qual-tr** — Üret(qwen32b+gemini paralel) → Kontrol(llama) → Polish(kimi2). Türkçe metin için.
3. **qual-analysis** — 3 perspektif(gptoss + kimi2 + gemini-pro paralel) → Sentez(gptoss). Analiz için.
4. **qual-translate** — Çevir(qwen32b) → Geri-çevir(kimi) → Karşılaştır(llama) → Düzelt(gptoss). Çeviri için.

### B) Race (4 pipeline — paralel yarış, ilk başarılı kazanır)
5. **race** — GPT-OSS vs Kimi vs Kimi2 (genel)
6. **race_code** — CF Kimi K2.5 vs Groq GPT-OSS 120B (kod)
7. **race_tr** — Qwen32B vs Gemini (Türkçe)
8. **race_local** — PC Phi4 vs PC Gemma2 (yerel model, opsiyonel)

### C) Quality+Humanize (3 pipeline — AI detector bypass)
9. **qual_human** — qual-tr + humanizer chain (AI-generated sound'u azalt)
10. **qual_code_human** — qual-code + humanize
11. **humanize_score** — input'un "AI-written" skorunu ver (0-1)

### D) Auto-verify (2 pipeline — PC GPU paralel)
12. **auto_verify_code** — granite-2b security + codellama test + deepseek lint (PC GPU 3 model paralel)
13. **auto_verify_turkish** — aya-8b TR gramer/stil kontrol

## Kaynaklar

**SERVER (Read-only):**
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/quick.py` (**2505 satır**) — ana pipeline logic:
  - `ask_pipeline(prompt, pipeline_type, diff_mode=False, file_path=None)` fonksiyonu
  - Chunk-based read: satır 1525-1950 civarı `ask_pipeline` tanımı + step helpers
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/mcp_tools/quality_tools.py` (135 satır) — quality tool register pattern
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/humanizer/` (AI-detect bypass logic)
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/mcp_tools/system_tools.py` (auto_verify wrapper'ları)

## Giriş (Mevcut — 005 sonrası)

- `core/backend/app/providers/` — 6 provider client (Groq, Cerebras, Gemini, CloudFlare, Cohere, Anthropic partial)
- `core/backend/app/cascade/` — breaker + cache + orchestrator
- `core/backend/app/mcp/tools/basic_providers.py` — 10 basic tool
- pytest: 46/46 yeşil
- Claude Code `mcp__abs__ask_*` çalışıyor

**Eksik provider'lar (bu task'ta tamamlanacak):**
- Anthropic full (Claude Haiku + Sonnet + Opus — Anthropic SDK)
- PC Ollama (phi4, gemma2, codellama, granite, aya, deepseek, starcoder) — opsiyonel, Ollama URL varsa

## Beklenen Çıktı

### 1. Pipeline Core (`core/backend/app/pipelines/`)

- [ ] `app/pipelines/__init__.py`
- [ ] `app/pipelines/base.py`:
  - `@dataclass PipelineStep` (name, func, args, elapsed, ok, result)
  - `@dataclass PipelineResult` (pipeline_type, steps, final_response, total_elapsed, prompt)
  - `class BasePipeline(ABC)` — `async def run(prompt: str) -> PipelineResult`
- [ ] `app/pipelines/execution.py`:
  - `async def run_parallel(*coros)` — `asyncio.gather`
  - `async def run_sequential(*steps)` — adım adım
  - `async def step(name, provider_call) -> PipelineStep` — timing + error yakalama

### 2. Quality Pipelines (`app/pipelines/quality/`)

- [ ] `app/pipelines/quality/code.py` — qual-code (kimi+gpt20 → codellama → gptoss)
- [ ] `app/pipelines/quality/turkish.py` — qual-tr (qwen32b+gemini → llama → kimi2)
- [ ] `app/pipelines/quality/analysis.py` — qual-analysis (3 perspektif → sentez)
- [ ] `app/pipelines/quality/translate.py` — qual-translate (4 adım roundtrip)

### 3. Race Pipelines (`app/pipelines/race/`)

- [ ] `app/pipelines/race/general.py` — race (gptoss vs kimi vs kimi2, ilk başarılı)
- [ ] `app/pipelines/race/code.py` — race_code (CF Kimi vs Groq GPT-OSS)
- [ ] `app/pipelines/race/turkish.py` — race_tr (Qwen32B vs Gemini)
- [ ] `app/pipelines/race/local.py` — race_local (PC Phi4 vs Gemma2, Ollama required)

### 4. Humanize Pipelines (`app/pipelines/humanize/`)

- [ ] `app/pipelines/humanize/scorer.py` — humanize_score (AI-detector skoru)
- [ ] `app/pipelines/humanize/transformer.py` — humanize chain logic
- [ ] `app/pipelines/humanize/qual_human.py` — qual_human (qual-tr + humanize)
- [ ] `app/pipelines/humanize/qual_code_human.py` — qual_code_human

### 5. Auto-Verify (`app/pipelines/verify/`)

- [ ] `app/pipelines/verify/code.py` — auto_verify_code (granite-2b + codellama + deepseek paralel)
- [ ] `app/pipelines/verify/turkish.py` — auto_verify_turkish (aya-8b)

**Not:** auto_verify PC Ollama gerektirir. Ollama URL yoksa graceful error.

### 6. MCP Tool Wrappers (`core/backend/app/mcp/tools/`)

- [ ] `app/mcp/tools/pipelines.py` — 13 tool wrapper:
  - `qual_code`, `qual_tr`, `qual_analysis`, `qual_translate`
  - `race`, `race_code`, `race_tr`, `race_local`
  - `qual_human`, `qual_code_human`, `humanize_score`
  - `auto_verify_code`, `auto_verify_turkish`
- [ ] `app/mcp/tools/__init__.py` — `register_pipeline_tools(mcp)` çağrısı

### 7. Anthropic Client Tamamlama

- [ ] `app/providers/anthropic.py` — Haiku + Sonnet + Opus tam destek
- [ ] 005'te partial kalan kısımları tamamla
- [ ] `app/mcp/tools/anthropic_tools.py` — `ask_haiku`, `ask_sonnet`, `ask_opus` tool'ları (3 yeni tool)

### 8. Test

- [ ] `tests/test_pipelines_quality.py`:
  - `test_qual_code_chain()` — mock 4 model → chain execution → result
  - `test_qual_tr_chain()`
  - `test_qual_analysis_synthesis()`
  - `test_qual_translate_roundtrip()`
- [ ] `tests/test_pipelines_race.py`:
  - `test_race_first_success_wins()` — mock 2 provider, biri hızlı → hızlı kazanır
  - `test_race_all_fail_returns_error()`
- [ ] `tests/test_pipelines_humanize.py`:
  - `test_humanize_score_range()` — 0-1 aralığı
  - `test_qual_human_chain()`
- [ ] `tests/test_auto_verify.py`:
  - `test_auto_verify_code_requires_ollama()` — Ollama URL yoksa error
  - `test_auto_verify_code_parallel_3_models()` (mock Ollama)

## Kısıtlar

- ❌ SERVER'a Write/Edit yasak
- ❌ Feature Parity Kuralı: 13 pipeline'ın hepsi zorunlu, basitleştirme yok
- ❌ Hardcoded model ID'leri (`gpt-oss-120b` gibi) → config'ten okusun (gelecek provider update resilience için)
- ✅ `asyncio.gather` parallel execution
- ✅ Pipeline step telemetrisi (telemetry 007+008'de bu datayı SSE'ye akıtır)
- ✅ Error handling: bir model fail → pipeline fail with clear error (retry sonraki task'ta)
- ✅ Model alias system: `"fast-reasoning"` → `{provider: gemini, model: gemini-2.5-flash}` mapping

## Delegation Yönergesi

### 1. SERVER pattern keşfi

```
Read /Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/quick.py offset=1525 limit=300
Read /Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/quick.py offset=1800 limit=200
Read /Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/mcp_tools/quality_tools.py
```

```
mcp__abs__rag_query "asyncio gather parallel llm pipeline execution python"
mcp__abs__rag_query "multi-model quality chain verify refine pattern"
```

### 2. Base pipeline için `qual_code` (TPD reset sonrası)

```
mcp__abs__qual_code
  prompt: "Async pipeline base class Python.
  - PipelineStep dataclass (name, func, elapsed, ok, result, error)
  - PipelineResult dataclass (pipeline_type, steps, final_response, total_elapsed)
  - BasePipeline ABC: async def run(prompt) -> PipelineResult
  - execution helpers: run_parallel (asyncio.gather), run_sequential, step wrapper (timing + try/except)"
```

### 3. qual-code pipeline için `qual_code`

```
mcp__abs__qual_code
  prompt: "qual_code pipeline class — 4 model chain:
  1. Parallel: kimi (CF) + gpt-oss-20b (Groq) → 2 draft
  2. Verify: codellama (Ollama) → select best draft
  3. Polish: gpt-oss-120b (Groq) → final
  Provider registry'den enjekte et. Pipeline telemetry step'lerde.
  Her step timeout 30s, fail → next step skip, error logla."
```

### 4. Diğer 12 pipeline için `ask_kimi` (batch — daha ucuz)

```
mcp__abs__ask_kimi
  "Bu 4 pipeline class'ını yaz:
  1. QualTrPipeline [spec]
  2. QualAnalysisPipeline [spec]
  3. QualTranslatePipeline [spec]
  4. RaceGeneralPipeline [spec]
  
  Aynı base class'tan inherit, provider registry kullan."
```

(Tool sayısı fazla olduğu için 3-4 ayrı batch çağrı TPM için)

### 5. MCP wrapper'lar için `ask_kimi`

```
mcp__abs__ask_kimi
  "13 FastMCP tool wrapper:
  @mcp.tool() async def qual_code(prompt: str) -> str:
      pipeline = QualCodePipeline(registry)
      result = await pipeline.run(prompt)
      return result.final_response
  [13 tool için aynı pattern]"
```

### 6. Anthropic SDK için `qual_code`

```
mcp__abs__qual_code
  prompt: "AnthropicProvider full implementation.
  - async def call(prompt, model) — Sonnet 4.6 + Haiku 4.5 + Opus 4.x
  - streaming support
  - token counting (client.messages.count_tokens)
  - Rate limit handling (retry-after header)
  - 3 tool wrapper: ask_haiku, ask_sonnet, ask_opus"
```

### 7. Test

```
mcp__abs__qual_code
  prompt: "pytest: 9 test for pipelines (quality 4, race 2, humanize 2, verify 1).
  Mock provider responses (respx).
  asyncio.gather parallel verification (wall time < 2s if both providers 1s).
  Fail scenarios dahil."
```

### 8. Final skor

```
mcp__abs__code_review tier="standard"
mcp__abs__judge_patch
```

### Hedef Delegation

- **Min %35 delegation** (13 pipeline + Anthropic + 13 tool wrapper = büyük scope)
- MCP çağrı **min 10 kez**

## Adımlar (sıra)

1. SERVER `quick.py` + `quality_tools.py` chunk read (pattern)
2. `rag_query` ile async pipeline pattern
3. pyproject.toml: `anthropic>=0.40`, `asyncio-timeout` (varsa)
4. `app/pipelines/base.py` + `execution.py` (`qual_code` delege)
5. `app/pipelines/quality/*.py` — 4 quality pipeline (batch delege)
6. `app/pipelines/race/*.py` — 4 race pipeline (batch delege)
7. `app/pipelines/humanize/*.py` — 3 humanize (batch delege)
8. `app/pipelines/verify/*.py` — 2 auto-verify (batch delege)
9. `app/providers/anthropic.py` full + tool wrapper (`qual_code` delege)
10. `app/mcp/tools/pipelines.py` — 13 tool wrapper (`ask_kimi` delege)
11. `app/mcp/tools/anthropic_tools.py` — 3 tool wrapper
12. `app/main.py` update: MCP tool registry güncelle (toplam 26 tool → 10+13+3)
13. Test yazımı (`qual_code` delege)
14. `pytest tests/ -q` → 46 önceki + min 10 yeni = 56+ passed
15. Docker build + up + Claude Code manuel test:
    ```
    mcp__abs__qual_code ile "Python fibonacci function yaz" test
    mcp__abs__qual_tr ile "Ürünümüzü Türkçe tanıt" test
    mcp__abs__race_code ile hız karşılaştırması
    ```
16. `code_review` + `judge_patch`
17. Summary

## Doğrulama

```bash
cd core/backend
.venv/bin/pytest tests/ -q
# Beklenen: min 56 passed

cd ../../infra
docker compose build backend
docker compose up -d

# Claude Code'da manuel test
# Terminal:
claude
# > mcp__abs__qual_code prompt="Fibonacci Python"
# Beklenen: 4-model chain çalışır, final_response içeren result
# Pipeline steps: [{name: 'parallel_drafts', elapsed: 3.2, ok: true}, {name: 'verify', ...}, ...]

# > mcp__abs__qual_tr prompt="React ne işe yarar kısaca açıkla"
# Beklenen: TR akıcı metin

# > mcp__abs__race_code prompt="Bubble sort JS"
# Beklenen: İlk başarılı provider'dan cevap (daha hızlı olan)
```

## Tamamlama

1. `git diff --stat`
2. `judge_patch` skor
3. `completed/006-pipelines-summary.md`:
   ```markdown
   ## Ne Yapıldı
   - 13 pipeline: Quality 4, Race 4, Humanize 3, Auto-verify 2
   - Anthropic provider full + 3 tool
   - 16 yeni MCP tool (10+13+3 → total 26)
   - N pytest

   ## Pipeline Model Zincirleri (dogrulama)
   - qual-code: kimi + gpt-oss-20b → codellama → gpt-oss-120b ✓
   - qual-tr: qwen32b + gemini → llama → kimi2 ✓
   - [13 pipeline detay]

   ## Delegation Kullanımı
   - TPD durumu (reset sonrası)
   - [detay]

   ## Claude Code Live Kanıtları
   - qual_code örnek çağrı screenshot
   - qual_tr örnek çağrı
   - race_code hız karşılaştırması

   ## Kalan
   - 65+ tool (007 hook, 008 kalan tool, 009 judge+workflow+RAG)
   - Pipeline step SSE stream'ine yazım 007'de (panel widget live update)
   ```
4. Task'ı `completed/`'e taşı
5. "006 tamam" rapor

---

**Tahmini süre:** 4-6 saat
**Sonraki task:** `007-hooks.md` — 5 hook modülü port (feature_nudge, delegate_nudge, plan_first, rag_inject, enrichment)
