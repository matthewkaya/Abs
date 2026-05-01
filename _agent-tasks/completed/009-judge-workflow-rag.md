# Task 009 — Workflow Durability + Judge Log + Cohere Alert + RAG Real

**Tahmini süre:** 3-4 saat (büyük task — 4 modül + 4 MCP tool real implementation + 4 yeni tool)
**Önkoşul:** 008 tamam (74 tool registered, 2 STUB: workflow_status + cohere_alert_status)

## Bağlam

008'de **74 MCP tool** kayıtlı. İki tanesi STUB:
- `workflow_status` → boş liste döndürüyor
- `cohere_alert_status` → sadece config var/yok kontrolü

Ayrıca 008'de **judge_patch** kayıtlı ama **judge log/stats yok** — her çağrı JSONL'e yazılmıyor, drift istatistiği yok.

**rag_query** SERVER'da 898 satırlık tam implementation; ürün tarafında **henüz yok**. RAG MCP tool'ları (rag_query, rag_status, rag_hybrid) eksik.

Bu task **4 modülü gerçek hale getirir**:
1. `workflow_state` (SQLite checkpoint) → `workflow_status` real
2. `judge_log` + `judge_stats` (JSONL drift tracker) → 2 yeni MCP tool
3. `cohere_alert` (quota threshold pipeline) → `cohere_alert_status` real
4. `rag` lite (ChromaDB + nomic-embed) → 3 yeni MCP tool

## Giriş (Mevcut Durum)

Worker `cd /Users/eneseserkan/Main/abs-server-product && pytest -x` ile **100/100 yeşil** görmeli.

Mevcut dosyalar (porlanacak referans **YASAK READ-ONLY**):
```
/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/workflow_state.py    (268 satır)
/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/judge_log.py         (234 satır)
/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/judge_stats.py       (139 satır)
/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/cohere_alert.py      (181 satır)
/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/rag.py               (898 satır — TOO BIG, sadece kritik path'leri al)
```

Mevcut STUB:
```
core/backend/app/mcp/tools/workflow_stub.py  (workflow_status + cohere_alert_status)
```

Bu dosya **sil**, yerine 4 yeni gerçek modül.

## Beklenen Çıktı

### A. Workflow Durability (real)

- [ ] `app/workflow/__init__.py` (re-export)
- [ ] `app/workflow/state.py` (~250 satır) — `start_workflow`, `record_step`, `finish_workflow`, `resume`, `get_workflow`, `list_workflows`, `cleanup_old`
  - SQLite path: `<data_dir>/workflow_state.db` (data_dir = `settings.data_dir`, default `/tmp/abs-data` veya `~/.abs/`)
  - Schema: `workflows(id, type, prompt_hash, started_at, finished_at, status)` + `steps(workflow_id, step_idx, name, status, result_json, started_at, finished_at)`
  - `start_workflow(type, prompt) -> workflow_id` (uuid4 hex 16 char)
  - `record_step(trace_id, step_name, status, result=None) -> step_id`
  - `finish_workflow(trace_id, status="ok")`
  - `resume(trace_id) -> dict` (son başarılı adımın result'ı + kalan adım sayısı)
  - `cleanup_old(days=30) -> int` (eskiyi sil)

- [ ] `app/mcp/tools/workflow.py` (~80 satır) — 2 tool:
  - `workflow_status() -> JSON` (active + recent + db_size_kb + by_status agg) — STUB değiştir
  - `workflow_resume(trace_id) -> JSON` — son başarılı adımdan devam state'i

- [ ] `tests/test_workflow_state.py` (~80 satır) — 4 test:
  - start + record + finish + get_workflow
  - resume sonrası kaldığı yer
  - cleanup_old (eski workflow + steps)
  - list_workflows status filter

### B. Judge Log + Drift Stats

- [ ] `app/judge/log.py` (~150 satır) — `log_judgment(result, file_path=None, source='judge_patch_tool') -> id` JSONL append
  - Path: `<data_dir>/judge_log.jsonl`
  - Schema: `{id, ts, source, file, ast_score, llm_score, combined_score, persona_drift, outcome}`
  - Log rotation: 5MB → `.1` yedek, sıfırla
  - `update_outcome(judgment_id, outcome: 'accept'|'reject') -> bool` (in-place line rewrite — dosya küçük, tolerable)

- [ ] `app/judge/stats.py` (~120 satır):
  - `aggregate(window_days=7) -> dict` — son N gün judgment'ları:
    - `count`, `avg_combined`, `avg_ast`, `avg_llm`
    - `outcome_counts` (accept/reject/null)
    - `drift_signal: 'stable'|'tightening'|'loosening'` (son 7 gün vs önceki 7 gün avg karşılaştırması, ±0.5 eşik)
    - `top_files: [{file, avg_score, n}]` (en çok değerlendirilen 5 dosya)
  - `recent(limit=20) -> list[dict]`

- [ ] `app/mcp/tools/judge_extras.py` (~70 satır) — 2 yeni tool:
  - `judge_stats(window_days: int = 7) -> JSON` — aggregate döner
  - `judge_recent(limit: int = 20) -> JSON` — son N kayıt

- [ ] `app/judge/senior.py` patch — `judge_diff()` sonucu döndermeden önce **`log_judgment(result)` çağır** (try/except, sessiz fail).
  - Mevcut `judge_diff` API kırılmamalı — sadece log side-effect ekle.

- [ ] `app/mcp/tools/quality.py` patch — `judge_patch` tool'unda log_judgment çağrısı kontrol (zaten senior.py log atıyorsa duplicate yazmasın).

- [ ] `tests/test_judge_log.py` (~80 satır) — 5 test:
  - log_judgment yazar + ID döner + JSONL parse
  - update_outcome accept yazar
  - aggregate window 7 gün
  - drift_signal tightening (test data: önceki avg 7.5 → şimdiki 6.5)
  - log rotation 5MB sonrası `.1` oluşur

### C. Cohere Alert Pipeline (real)

- [ ] `app/cohere/__init__.py` (re-export)
- [ ] `app/cohere/alert.py` (~180 satır) — port `SERVER/orchestrator/cohere_alert.py`:
  - Path: `<data_dir>/cohere_usage.json` + `<data_dir>/cohere_alerts.jsonl` + `<data_dir>/cohere_alerts_seen.json`
  - Thresholds: `[(75,'warn'), (90,'danger'), (100,'limit_hit')]`
  - `track_usage(count: int, limit: int = 1000) -> str|None` — kullanım güncelle, eşik tetikle
  - `read_recent(limit=20) -> list`
  - `mark_acknowledged(alert_id) -> bool`
  - Idempotency: her ay her threshold sadece 1x

- [ ] `app/providers/cohere.py` patch — her successful Cohere API call sonrası `track_usage(usage_count, limit=1000)` çağır.
  - Aylık counter `data_dir/cohere_usage.json` içinde `{month: 'YYYY-MM', count: N}` formatı.
  - Yeni ay → reset.

- [ ] `app/mcp/tools/cohere_alert.py` (~90 satır) — STUB workflow_stub.py'deki `cohere_alert_status` SİL, gerçeğini yaz:
  - `cohere_alert_status() -> JSON` — `{configured, used_today, used_month, limit, percent, last_alert, alerts_count_24h, warning, severity}`
  - `cohere_alerts_recent(limit: int = 10) -> JSON` — son alert'ler
  - `cohere_alert_ack(alert_id: str) -> JSON` — ack işaretle

- [ ] `tests/test_cohere_alert.py` (~80 satır) — 5 test:
  - track_usage 80% → 'warn' tetikler, 81% tekrar tetiklemez (idempotent)
  - 91% → 'danger', 100% → 'limit_hit'
  - read_recent FIFO order
  - mark_acknowledged dosyaya yazar
  - yeni ay → counter reset

### D. RAG (lite, multi-tenant)

- [ ] `app/rag/__init__.py` (re-export)
- [ ] `app/rag/indexer.py` (~250 satır):
  - ChromaDB persistent client: `<data_dir>/rag_chroma/`
  - Embedding: Ollama `nomic-embed-text` (default endpoint `http://localhost:11434`, env `ABS_OLLAMA_URL`)
  - `index_path(path: str, project: str = 'default', extensions=None) -> dict` (count_indexed, count_skipped)
  - Skip dirs: `node_modules, .git, .venv, __pycache__, dist, build, .next, vendor`
  - Default extensions: `.md, .py, .ts, .tsx, .js, .json, .sh, .css, .html`
  - Chunk size: 1500 char (basit char-split, semantic split YOK — basit tut)
  - Metadata: `{project, file, chunk_idx, hash}`
  - Skip if hash unchanged (re-index idempotency)
  - `clear(project=None) -> int` (collection sil veya filter)

- [ ] `app/rag/query.py` (~120 satır):
  - `query(question: str, project_filter=None, top_k=5) -> list[{file, snippet, score, project}]`
  - Cosine similarity (ChromaDB default)
  - Snippet: ilk 200 char
  - `status() -> dict` (collections, total_chunks, db_size_mb)

- [ ] `app/mcp/tools/rag.py` (~120 satır) — 4 tool:
  - `rag_index(path: str, project: str = 'default') -> JSON` (count + skipped)
  - `rag_query(question: str, project_filter: str | None = None, top_k: int = 5) -> JSON`
  - `rag_status() -> JSON`
  - `rag_clear(project: str | None = None) -> JSON`

- [ ] `pyproject.toml` patch:
  - `chromadb>=0.4.22`
  - `httpx>=0.27` (Ollama için zaten var muhtemel — kontrol et)

- [ ] `tests/test_rag.py` (~100 satır) — 4 test (Ollama YOKSA skip):
  - `pytest.importorskip('chromadb')`
  - `index_path` küçük tmpdir (3 .md dosya) → count=3
  - `query` indexlenenden snippet döner
  - `status` chunks > 0
  - `clear(project='test')` collection siler
  - **Embed mock:** Ollama erişilemezse `monkeypatch` ile fake embed (random 768-dim float list) — testler offline çalışmalı

### E. Registry + Cleanup

- [ ] `app/mcp/server.py` patch — `register_all_tools()` içine 4 yeni modül import:
  - `from app.mcp.tools import workflow, judge_extras, cohere_alert, rag`
  - **DİKKAT:** Bu dosyaya 008'de Edit 3x atlandı; **`Write` ile tam override** kullan (önce Read, sonra Write ile yeniden yaz).

- [ ] `app/mcp/tools/workflow_stub.py` **SİL** (rm) — yeni `workflow.py` ve `cohere_alert.py` tarafından replace edildi.
- [ ] `tests/test_tools_count.py` patch — beklenen tool sayısı `74 → 82` (4 yeni: workflow_status (real), workflow_resume, judge_stats, judge_recent + 4 yeni: cohere_alerts_recent, cohere_alert_ack, rag_index, rag_query, rag_status, rag_clear). **NET: +10 tool, toplam 84.** Sayım doğrula `pytest tests/test_tools_count.py -v`.
  - Kritik tool listesinde yeni isimleri ekle: `workflow_resume, judge_stats, judge_recent, cohere_alerts_recent, cohere_alert_ack, rag_index, rag_query, rag_status, rag_clear`.

## Kısıtlar

- **Python 3.11+**
- **chromadb>=0.4.22** — `pip install` test
- Ollama (nomic-embed-text) erişilemezse RAG testleri `monkeypatch` ile fake embed kullanmalı (offline CI gereksinimi)
- **SERVER dokunulmaz** — sadece Read referans
- 008'de tracker.bump async fix yapıldı — yeni tool'larda **`await tracker.bump('tool_name')`** kullan
- Her yeni tool **`@mcp_server.tool()` + `@with_hooks('tool_name')` + `await tracker.bump`** üçlüsü
- `data_dir` settings'ten gel — testlerde `tmp_path` kullan
- pytest 100/100 zorunlu — bir test bile fail bırakma

## Adımlar (Worker Claude için)

1. **Pattern oku** (chunked, head -100):
   - `Read SERVER/orchestrator/workflow_state.py 1-100`, sonra 100-200, 200-268
   - `Read SERVER/orchestrator/judge_log.py 1-100`, sonra 100-234
   - `Read SERVER/orchestrator/judge_stats.py 1-139`
   - `Read SERVER/orchestrator/cohere_alert.py 1-181`
   - `Read SERVER/orchestrator/rag.py 1-150` (sadece init+config), 200-400 (chunk+embed), 600-700 (query)
   - **TÜM dosyayı okuma** — token tasarrufu

2. **Module 1: workflow_state**
   - `app/workflow/state.py` yaz (port edilmiş, `data_dir` settings + uuid4 trace_id)
   - `app/mcp/tools/workflow.py` (workflow_status + workflow_resume)
   - `tests/test_workflow_state.py` (tmp_path, 4 test)
   - `pytest tests/test_workflow_state.py -v` → 4 PASS

3. **Module 2: judge_log + stats**
   - `app/judge/log.py` (port + `update_outcome`)
   - `app/judge/stats.py` (aggregate + drift_signal)
   - `app/judge/senior.py` patch — `judge_diff()` sonunda `log_judgment(result)` ekle (try/except)
   - `app/mcp/tools/judge_extras.py` (judge_stats + judge_recent)
   - `tests/test_judge_log.py` (5 test)
   - `pytest tests/test_judge_log.py tests/test_judge_senior.py -v` → 9 PASS (4 eski + 5 yeni)

4. **Module 3: cohere_alert**
   - `app/cohere/alert.py` (port — threshold cycle, idempotent)
   - `app/providers/cohere.py` patch — her başarılı call sonrası `track_usage(count, limit)`
   - `app/mcp/tools/cohere_alert.py` (3 tool)
   - `tests/test_cohere_alert.py` (5 test, tmp_path)
   - `pytest tests/test_cohere_alert.py -v` → 5 PASS

5. **Module 4: RAG**
   - `pip install chromadb`
   - `app/rag/indexer.py` + `app/rag/query.py`
   - `app/mcp/tools/rag.py` (4 tool)
   - `tests/test_rag.py` (4 test, monkeypatch fake embed)
   - `pytest tests/test_rag.py -v` → 4 PASS

6. **Registry + cleanup**
   - `app/mcp/tools/workflow_stub.py` **SİL** (`rm` veya boş bırak — `register_all_tools` import'undan sil)
   - `app/mcp/server.py` Read → tam Write override (4 yeni import + workflow_stub.py kaldır)
   - `tests/test_tools_count.py` patch (74 → 84 + yeni tool isim listesi)

7. **Tam test suite**
   - `pytest -x` → 100% PASS (önceki 100 + ~28 yeni = ~128)
   - `pytest -q` ile sayı doğrula

8. **Live MCP smoke** (Worker'ın yapabileceği basit kanıt):
   - Backend boot: `cd core/backend && uvicorn app.main:app --port 8000 &`
   - `claude mcp add abs-009 http://localhost:8000/mcp/` (eğer test hesabı varsa)
   - `mcp list` → `abs-009 ✓ Connected, 84 tools`
   - 4 canlı kanıt: `workflow_status`, `judge_stats`, `cohere_alert_status`, `rag_status` (her biri valid JSON dönsün)

## Doğrulama

```
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pip install chromadb
.venv/bin/pytest -q                                    # >= 128 passed
.venv/bin/pytest tests/test_tools_count.py -v          # 84 tool guard
.venv/bin/python -c "from app.mcp.server import mcp_server; print(len(mcp_server._tools))"  # 84
```

## Tamamlama

Bitirince `_agent-tasks/completed/009-judge-workflow-rag-summary.md` yaz:
- Ne yapıldı (4 modül + 10 yeni tool listesi)
- Delegation kullanımı (kalite pipeline kullandın mı, hangi modeller, neden)
- Atlanan/blocker (ChromaDB install fail vs. Ollama offline davranışı vs.)
- Test sonuçları (kaç test, kaç PASS)
- Live MCP smoke (4 tool JSON kanıtı varsa)
- Bu task'ı `completed/` altına taşı

## Notlar Planlayıcıya (raporda doldur)

- Workflow durability `qual_code/qual_analysis` pipeline'larına bağlanması 010'a mı kalsın yoksa burada mı? (Önerim: 010 — bu task zaten büyük)
- Judge live training (persona threshold dynamic adjust) 011'e bırakıldı — şimdilik sadece log + stats yeterli
- MLX provider 010'a — bu task'ta MLX YOK
- RAG semantic chunk-split (basit char-split yerine) 011'e — basit yeterli

## Feature Parity Kuralı (HATIRLATMA)

SERVER'daki workflow_state, judge_log, judge_stats, cohere_alert, rag modüllerinin **tüm public fonksiyonları** porlamak zorunlu. "Şimdi lazım değil" denerek hiçbiri atlanmaz. Eğer atlanmak istenirse summary.md'de gerekçe + planlayıcı onay gereği belirt.
