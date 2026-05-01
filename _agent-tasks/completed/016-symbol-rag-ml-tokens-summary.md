# Task 016 — Symbol Graph + RAG Hybrid + ML Persona + Real Token Tracking (SUMMARY)

**Tamamlandı:** 2026-04-25
**Süre:** ~1.5 saat (planlanan 4h altında)
**Sonuç:** 4 modül + 3 yeni MCP tool + 2 mevcut test fix.

> **🎉 BU SON INNOVATION TASK** — Production feature parity ve farklılaştırıcı katmanlar tamamlandı.
> 017+ artık ürünleştirme aşaması: panel UI polish, customer onboarding email, marketplace listing, multi-language docs, performance benchmarks.

## Özet

| Hedef | Önce | Sonra | Δ |
|-------|------|-------|---|
| pytest yeşil | 247 + 2 skip | **270 passed + 2 skipped** | +23 |
| MCP tool sayısı | 99 | **102** (`symbol_search`, `rag_hybrid`, `judge_persona_predict`) | +3 |
| Symbol Graph endpoints | stub `[]` | gerçek AST + SQLite | yeni |
| RAG hybrid | sadece cosine | BM25 + cosine fusion | yeni |
| Judge persona | drift heuristic v1 | ML logistic regression v2 | yeni |
| Token tracking | sadece count_24h | tokens_in_24h + tokens_out_24h | yeni |

## Modul A — Symbol Graph (Python AST + SQLite)

**Yeni dosyalar:**
- `app/symbols/parser.py` (~115 satır) — `Symbol` dataclass + `parse_python_file` + `parse_directory`. Visitor pattern: `FunctionDef`, `AsyncFunctionDef`, `ClassDef`, `Import`, `ImportFrom`. Fonksiyon içindeki `ast.Call` → `edges_out`. Nested class.method → `parent` set.
- `app/symbols/store.py` (~120 satır) — SQLite tablolar: `symbols(name, kind, file, lineno, parent)` + `edges(from_sym, to_sym, file)`. CRUD: `bulk_insert`, `search(LIKE %q%, kind?)`, `neighbors(name, depth=1)` BFS, `stats()`, `reset()`.
- `app/symbols/index.py` (~25 satır) — `index_path(path, replace=False)` orchestrator.
- `app/symbols/__init__.py` — re-export.

**Patch:** `app/api/symbol_graph.py` (tam Write override) — 4 endpoint:
- `GET /api/symbol-graph/neighbors?name=X&depth=N` (1-5 depth)
- `GET /api/symbol-graph/search?q=X&kind=function|class|import&limit=50`
- `GET /api/symbol-graph/stats`
- `POST /api/symbol-graph/index` body `{path, replace}`

**Yeni test:** `tests/test_symbols_parser.py` (6 test) → **6/6 PASS** (5 zorunlu + 1 ek index)
- functions extraction (def + async def)
- class with methods (parent set)
- import + ImportFrom
- neighbors depth 1 (BFS edge bidirectional)
- substring search
- index_path inserts with stats

**Regression patch:** `tests/test_panel_widgets.py` 2 test güncellendi — eski stub `status:"empty"` + `note:"009-rag"` artık yok. Yeni davranış: `status: "not_found"` (DB boşsa) veya `"ok"` (sembol varsa). `name` max_length 256'ya yükseldi.

## Modul B — RAG Hybrid (BM25 + Cosine Fusion)

**Yeni dosya:** `app/rag/hybrid.py` (~110 satır)
- `_tokenize(text)` — `\w+` lowercase
- `_bm25_score(q_toks, doc_toks, ...)` — k1=1.5, b=0.75 standart BM25
- `_normalize(arr)` — min-max scale [0,1]
- `query_hybrid(question, project_filter?, top_k=5, alpha_semantic=0.6)`:
  - Embed → Chroma top 30 (pool_size = max(top_k*6, 30))
  - BM25 score her doc için
  - Cosine score = 1.0 - distance
  - Min-max normalize her iki skor
  - `fused = alpha * cos_n + (1-alpha) * bm25_n`
  - Top-K döner: `{file, project, snippet[:220], score, bm25, cosine}`

**Yeni test:** `tests/test_rag_hybrid.py` (6 test) → **6/6 PASS** (5 zorunlu + 1 ek normalize)
- `_tokenize_basic`, `_bm25_higher_for_keyword_match`, `_normalize_min_max`
- `query_hybrid_empty_question` → []
- `query_hybrid_uses_both_signals` (mocked Chroma + embed)
- `alpha_zero_pure_bm25` — keyword match ilk sırada (cosine high düşer)

## Modul C — ML Persona Training v2

**Yeni dosya:** `app/judge/ml_persona.py` (~125 satır)
- 3-feature: ast_score (0-10), llm_score (0-10), persona_drift (0-2)
- `_sigmoid(x)` overflow-safe (positive/negative path)
- `_train_logistic(X, y)` — saf Python gradient descent (200 epoch, lr=0.05)
- `train_ml(min_samples=20)` — judge_log entries → train + persist `cache_dir/persona_ml_model.json`
- `predict_accept(ast, llm, drift)` — sigmoid → `{p_accept, decision, model_n_samples}`
- `model_status()` — trained / not trained

**SAF PYTHON, sklearn yok** — task spec kuralı.

**Yeni test:** `tests/test_judge_ml_persona.py` (5 test) → **5/5 PASS** (4 zorunlu + 1 ek error handling)
- `train_insufficient_data` (<20 samples)
- `train_with_sufficient_samples` (15 accept high-score + 15 reject low-score)
- `predict_high_score_accepts` — train sonra (8.5, 8.0, 0.1) → accept
- `predict_low_score_rejects` — (2.0, 2.0, 1.0) → reject
- `predict_without_training_returns_error`

## Modul D — Real Token Tracking

**Patch'ler:**
- `app/mcp/tracking.py` — `ToolUsage` `tokens_in_24h` + `tokens_out_24h` alanları, `bump(name, *, tokens_in=0, tokens_out=0)` keyword-only kwargs (backward compat). `snapshot()` token alanları döner.
- `app/pipelines/execution.py::timed_step` — ProviderResponse `tokens_in/out` → `step.meta["tokens_in"]/["tokens_out"]` forward.
- `app/mcp/tools/pipelines.py` — 4 quality pipeline tool (`qual_code`, `qual_tr`, `qual_analysis`, `qual_translate`) `_sum_tokens(res)` helper'ı ile pipeline result'tan token toplar, `tracker.bump(name, tokens_in=ti, tokens_out=to)` çağırır. Race/humanize/verify pipeline tool'ları aynı pattern'le güncellenebilir 017+'da (mekanik refactor).
- `app/billing/cost_estimator.py` — gerçek token varsa kullan (`exact: true`), yoksa eski avg 1500 fallback (`exact: false`). Note dynamic: gerçek token aktifken "Gercek token tracking aktif (016)", aksi halde fallback notu.

**Yeni test:** `tests/test_token_tracking.py` (6 test) → **6/6 PASS** (4 zorunlu + 2 ek backward-compat + step.meta forward)
- `tracker_bump_accepts_tokens`
- `tracker_bump_accumulates`
- `tracker_bump_backward_compat_no_tokens` — eski `bump(name)` hâlâ çalışır
- `cost_estimator_uses_real_tokens_when_available` — `exact:true`, hesap doğru
- `cost_estimator_falls_back_to_avg` — count_24h>0 + tokens=0 → 1500 avg
- `step_meta_tokens_forwarded` — timed_step ProviderResponse → step.meta

**Regression:** `tests/test_cost_estimator.py` 5/5 PASS — eski avg fallback testleri hâlâ yeşil (note string assertion da koruyor).

## Modul E — 3 MCP Tools + 102 Guard

**Yeni dosya:** `app/mcp/tools/innovation_tools.py` (~55 satır, 3 tool)
- `symbol_search(q, kind?, limit=20)` — Symbol DB substring search
- `rag_hybrid(question, project_filter?, top_k=5, alpha_semantic=0.6)`
- `judge_persona_predict(ast, llm, drift)` — ML model load + sigmoid predict

**Patch:** `app/mcp/server.py` (tam Write override) — `innovation_tools` import + count
**Patch:** `tests/test_tools_count.py` — 99 → **102 guard**, must_have'a 3 tool

**Test:** 2/2 PASS. `_REGISTERED_COUNT == 102`.

## Test Sonuçları

```
.venv/bin/pytest -q
270 passed, 2 skipped in 6.86s
```

**Önce:** 247 + 2 skip. **Sonra:** 270 + 2 skip. **Hedef:** 268+. **+23 yeni test:**
- test_symbols_parser.py: 6
- test_rag_hybrid.py: 6
- test_judge_ml_persona.py: 5
- test_token_tracking.py: 6
- test_tools_count.py: 0 (mevcut 2 test 102 guard'a güncellendi)

**+2 SKIP** 013'ten korundu (sops binary).

**Mevcut testler korundu:**
- test_panel_widgets.py 2 test güncellendi (016 yeni davranış: not_found + max_length 256). Tüm panel widget testleri yeşil.
- test_cost_estimator.py 5/5 PASS — backward compat note kontrolu.
- test_pipelines_quality.py vb. 4 quality pipeline'a token forward eklenmesi mevcut testleri etkilemedi.

## Live MCP Smoke (Kanıtlar `/tmp/abs-016-smoke/evidence/`)

uvicorn `--port 8771` (env: `ABS_UPDATE_SIGNATURE_REQUIRED=false` dev mode).

### 1. `POST /api/symbol-graph/index app/main.py` — 34 sembol indexlendi
```json
{
  "path": ".../app/main.py",
  "indexed": 34,
  "stats": {
    "total_symbols": 34,
    "total_edges": 16,
    "by_kind": {"function": 3, "import": 31}
  }
}
```
3 fonksiyon (`lifespan`, `setup_index`, `healthz`) + 31 import + 16 call edge.

### 2. `symbol_search "lifespan"` (MCP) — bulundu
```json
{
  "query": "lifespan",
  "kind": null,
  "results": [
    {"name": "lifespan", "kind": "function",
     "file": ".../app/main.py", "lineno": 31}
  ]
}
```

### 3. `rag_hybrid "what is workflow"` (MCP) — Chroma boş, [] döner
```json
[]
```

### 4. `judge_persona_predict (8.0, 7.5, 0.2)` (MCP) — model trained değil
```json
{"error": "model not trained yet — call train_ml first"}
```

MCP tools/list = **102**. Tüm 4 kanıt valid JSON.

## Notlar Planlayıcıya

1. **TypeScript/JS symbol parsing 017+'a** — sadece Python AST. tree-sitter veya esprima ile JS/TS parser ayrı modul olarak eklenebilir.

2. **Symbol DB cron re-index yok** — file change detection eksik. Manuel `POST /api/symbol-graph/index` veya watchdog tarafından scheduler 017'de.

3. **RAG hybrid `alpha_semantic` default 0.6** — empirik. Müşteri panel'de slider ile tune edebilir 017+'da (`ABS_RAG_ALPHA_SEMANTIC` env).

4. **ML persona threshold 0.5 sabit** — ROC AUC ile optimal threshold 017+'da. Şu an deterministik logistic regression yeterli (saf Python, sklearn yok).

5. **Token forward sadece 4 quality pipeline'da** — race/humanize/verify pipeline tool'larında forward eklenmedi. Mekanik refactor; cost değeri sınırlı (race tek-shot, humanize text-level). 017+'da kapsamlı patch.

6. **`basic_providers.ask_*` tool'larında token forward yok** — `_call(provider, prompt, ...)` helper provider response döner ama tool wrapper bump'a token geçirmiyor. 017+'da `_call` refactor + her ask_* tool'da forward eklenebilir; provider call cache'ten gelirse `cached:True` ProviderResponse zaten tokens=0 döner (cost yanılmaz).

7. **Cost estimator note dinamik** — `exact:true` varsa "Gercek token tracking aktif (016)", yoksa "Token sayisi tahmini (1500 avg, 30/70 split)". Panel'de "Gerçek/Tahmini" badge gösterilebilir 017'de.

8. **Symbol parsing skip dirs** — `.venv`, `node_modules`, `.git`, `__pycache__`, `dist`, `build`, `.next`, `.pytest_cache`, `.cache`. Müşteri büyük monorepo'larda customize istemiyor — yeterli.

9. **`app.symbols.__init__` gibi pattern** — 014/health'te yaşadığımız submodule shadow problemi burada yok çünkü class/fn re-export eden `__init__.py` `parser`/`store`/`index` modüllerini gölgelemiyor (instance değil function/class export).

10. **`ml_persona` model file `cache_dir/persona_ml_model.json`** — vault'a yazılmadı (cleartext değil, sadece weights). Model dosyası kaybolursa retrain mümkün; backup gerekmiyor.

## Feature Parity

016 SERVER paritesinden **ileriye geçer**:
- Symbol graph: SERVER'da yarım (sadece import_graph.json), ABS'de tam AST + SQLite + neighbors BFS + search.
- RAG hybrid: SERVER `query_hybrid` pattern'ı port edildi (rag.py:625), ABS'de daha temiz fusion.
- ML persona: SERVER'da yok, ABS-only innovation.
- Token tracking: SERVER'da yok, ABS-only cost transparency.

**Atlanan parity yok.**

## Doğrulama (Fail-Fast)

```bash
$ .venv/bin/pytest -q
270 passed, 2 skipped in 6.86s

$ .venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
102

$ .venv/bin/python -c "from app.symbols.parser import parse_python_file; from pathlib import Path; print(len(parse_python_file(Path('app/main.py'))))"
34

$ .venv/bin/python -c "from app.judge.ml_persona import model_status; print(model_status())"
{'trained': False}
```

Hepsi yeşil.

## Bu Task Sonrası

**016 = SON INNOVATION TASK.** Production feature parity tamamlanmış, ABS müşteri için satışa hazır:
- 102 MCP tool (Claude Code'dan kullanılabilir)
- 270 test (regression korumalı)
- Encrypted vault (013), license/refund (011), setup wizard (012), update channel + signature (014/015), real cost tracking (015/016), symbol graph + RAG hybrid + ML persona (016)

### 017+ Roadmap (ürünleştirme)

- Panel UI polish (rotation form, vault status banner, daily cost graph, ML predict slider)
- Customer onboarding email serisi (welcome → demo expiring → conversion)
- Marketplace listing (DigitalOcean Marketplace, Hetzner Cloud, AWS AMI)
- Multi-language docs (TR + EN, docs.automatiabcn.com)
- Performance benchmarks (req/s, MCP tool latency, RAG/symbol query bench)
- TypeScript/JS symbol parsing (tree-sitter)
- Symbol DB file watch + cron re-index
- RAG alpha tuning UI
- ML persona ROC threshold optimization
- Token tracking provider-level (basic_providers full refactor)
- Multi-tenant (tenant_id prefix in cache, vault, learnings)
- Symbol graph görselleştirme (panel widget, force-directed)

## Kapsam Dışı (017+'a)

- TypeScript/JS symbol parsing (tree-sitter)
- Symbol DB cron re-index + file watch
- RAG alpha tuning UI (panel slider)
- ML persona ROC threshold optimization
- Token tracking provider-level refactor (basic_providers `_call` helper)
- Multi-tenant symbol DB
- Symbol graph görselleştirme (panel widget)
- Race/humanize/verify pipeline token forward
- Hook delegate_nudge → learnings.log integration
