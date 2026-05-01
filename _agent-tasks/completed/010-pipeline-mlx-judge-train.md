# Task 010 — Workflow×Pipeline + MLX + Judge Live Training + RAG Semantic + Dockerfile

**Tahmini süre:** 3-4 saat (5 paralel modül + ~16 yeni test + Dockerfile/pyproject patch)
**Önkoşul:** 009 tamam (84 MCP tool registered, 118/118 pytest yeşil)

## Bağlam

009 sonunda 4 yeni gerçek modül (workflow / judge log+stats / cohere_alert / rag) bağlandı ama **birbirine ve pipeline'lara hâlâ bağlı değil**. 010 bu bağları kurar + 4 net yeni yetenek ekler:

1. **Workflow ↔ Pipeline entegrasyonu** — `qual_*` ve `qual_*_human` pipeline'ları opt-in olarak `start_workflow + record_step + finish_workflow` çağırsın. Panel SSE `mcp-tools` ve `budget-today` event'leri **gerçek `tracker.snapshot()` + `workflow.stats()`** versin (placeholder random kalksın).
2. **MLX provider** — Apple Silicon Neural Engine (M4) için `app/providers/mlx.py`. SERVER `quick.py:1828` patternine sadık HTTP client (`http://localhost:11436/v1/generate`). 2 yeni MCP tool: `ask_mlx`, `ask_mlx_fast`.
3. **Judge live training** — `app/judge/persona.py` şu an hardcoded `DEFAULT_PERSONA`. Live training: `judge_log.jsonl` outcome (`accept`/`reject`) okunup persona threshold dynamic adjust. 3 yeni MCP tool: `judge_persona_status`, `judge_persona_train`, `judge_persona_reset`.
4. **RAG semantic chunk-split** — şimdi `_CHUNK_CHARS=1500` body sliding. AST-aware split: Python `function/class def` boundary, Markdown `# heading` boundary. `index_path(..., chunk_strategy="semantic"|"char")` parametresi.
5. **Dockerfile + pyproject.toml patch** — 008/009 install'larında **pyproject.toml'a yazılmamış** dependency'ler (kritik regresyon riski!): `cohere>=5.13`, `chromadb>=0.4.22`. Dockerfile build deps: `apt-get install -y patch libsqlite3-dev gcc g++` (chromadb rust binding + patch_engine için).

**Tool sayısı hedefi:** 84 → **89+ tool** (+2 mlx + 3 judge_persona = 5 net).
**Test sayısı hedefi:** 118 → **~134+ test** (+16: 4 workflow integration, 3 mlx, 4 judge persona, 4 rag chunker, +1 sse real data).

## Giriş (Mevcut Durum — Worker bunu doğrulamadan başlasın)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                 # 118 passed beklenir
.venv/bin/python -c "import chromadb, cohere; print(chromadb.__version__, cohere.__version__)"
# 1.5.8 6.1.0 → venv'de kurulu ama pyproject.toml'da YOK (010'da düzelt)
```

**Mevcut dosyalar (modify edilecek):**
- `core/backend/pyproject.toml` (eksik 2 dep)
- `core/backend/Dockerfile` (build deps eksik)
- `core/backend/app/config.py` (`workflow_durable`, `mlx_url` eklenecek)
- `core/backend/app/pipelines/quality/{code,turkish,analysis,translate}.py` (workflow hook ekle)
- `core/backend/app/pipelines/humanize/{qual_human,qual_code_human}.py` (workflow hook ekle)
- `core/backend/app/judge/persona.py` (training fn'ları ekle)
- `core/backend/app/rag/indexer.py` (chunk_strategy parametresi)
- `core/backend/app/api/stream.py` (`_build_mcp_tools` + `_build_budget` real)
- `core/backend/app/mcp/server.py` (`register_all_tools` import + count)
- `core/backend/app/providers/registry.py` (mlx provider)
- `core/backend/tests/test_tools_count.py` (84 → 89 + yeni isimler)

**Yeni dosyalar:**
- `core/backend/app/providers/mlx.py`
- `core/backend/app/rag/chunker.py`
- `core/backend/app/judge/training.py`
- `core/backend/app/mcp/tools/judge_persona.py`
- `core/backend/app/workflow/integration.py` (helper: `wrap_pipeline_with_workflow`)
- `core/backend/tests/test_workflow_pipeline_integration.py`
- `core/backend/tests/test_provider_mlx.py`
- `core/backend/tests/test_judge_persona_training.py`
- `core/backend/tests/test_rag_chunker.py`
- `core/backend/tests/test_stream_real_data.py`

**Referans (READ-ONLY — sadece pattern oku, asla edit):**
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/quick.py:1828-1867` — `ask_mlx` HTTP pattern
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/quick.py:1750-1825` — pipeline×workflow_state örnek (qual_human için `_ws.start_workflow + record_step + finish_workflow`)
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/judge_persona.py` (varsa) — live training algoritması
- `/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/rag.py` — semantic split pattern (varsa)

## Beklenen Çıktı

### A. Workflow ↔ Pipeline Integration (opt-in)

**Yeni dosya** `app/workflow/integration.py` (~80 satır):

```python
"""Pipeline × workflow_state durability bağlayıcı.

Her pipeline.run() çağrısı:
  ABS_WORKFLOW_DURABLE=1 → start_workflow + record_step + finish_workflow
  ABS_WORKFLOW_DURABLE=0 → no-op (eski davranış)

Settings.workflow_durable runtime'da değiştirilebilir.
"""
from __future__ import annotations
import logging
from typing import Optional
from app.config import settings
from app.workflow import start_workflow, record_step, finish_workflow

logger = logging.getLogger(__name__)

class WorkflowSession:
    """Pipeline tarafında kullanılır. ABS_WORKFLOW_DURABLE off ise tüm metodlar no-op."""
    def __init__(self, wf_type: str, prompt: str):
        self.trace_id: Optional[str] = None
        self.wf_type = wf_type
        if settings.workflow_durable:
            try:
                self.trace_id = start_workflow(wf_type, prompt)
            except Exception as exc:
                logger.info("workflow start fail (silent): %s", exc)

    def step(self, name: str, status: str = "ok", result: dict | None = None) -> None:
        if not self.trace_id:
            return
        try:
            record_step(self.trace_id, name, status, result)
        except Exception as exc:
            logger.info("workflow step fail: %s", exc)

    def finish(self, status: str = "ok") -> None:
        if not self.trace_id:
            return
        try:
            finish_workflow(self.trace_id, status)
        except Exception as exc:
            logger.info("workflow finish fail: %s", exc)
```

**Patch:** `app/pipelines/quality/code.py` (`QualCodePipeline.run`):

- `run` başında: `wf = WorkflowSession("qual-code", prompt)`
- Her `steps.append(...)` sonrası: `wf.step(step_name, "ok" if step.ok else "fail", {"model": step.model, "elapsed_ms": step.elapsed_ms})`
- `return` öncesi: `wf.finish("ok" if not error else "fail")`
- `PipelineResult` döndermeden önce `result_dict["workflow_trace_id"] = wf.trace_id` (varsa) — `to_dict()` zaten `pipeline_type` veriyor, ekstra alan eklenmesi `_format_meta` sonunda `[workflow: {trace_id}]` olarak görünsün.

**Aynı patch:** `turkish.py`, `analysis.py`, `translate.py`, `humanize/qual_human.py`, `humanize/qual_code_human.py` — 6 pipeline.

**Config:** `app/config.py` ekle:
```python
workflow_durable: bool = False  # 010 — pipeline'lar SQLite checkpoint yazar mı
mlx_url: str = ""                # 010 — MLX bridge URL (boşsa graceful)
```

**SSE real-data:** `app/api/stream.py` patch:

- `_build_mcp_tools` → `tracker.snapshot()`'tan top-N tool count (random tablo gitsin):
  ```python
  from app.mcp.tracking import tracker
  def _build_mcp_tools() -> dict:
      snap = tracker.snapshot()
      tools = sorted(
          [{"name": k, "count_24h": v["count_24h"]} for k, v in snap.items()],
          key=lambda x: -x["count_24h"]
      )[:8]
      return {"tools": tools, "total_24h": sum(t["count_24h"] for t in tools)}
  ```
- `_build_budget.workflow` → `app.workflow.stats()` (count + recent listesi):
  ```python
  from app.workflow import stats as workflow_stats, list_workflows
  def _build_budget() -> dict:
      today = round(random.uniform(0.80, 4.20), 2)  # bütçe placeholder kalır (010 dışı)
      wf = workflow_stats()
      recent = list_workflows(limit=5)
      return {
          "today_usd": today,
          "projected_monthly_usd": round(today * 30, 2),
          "learnings_count": random.randint(440, 480),  # 010 dışı
          "workflow": {
              "summary": f"{wf.get('by_status', {}).get('ok', 0)}/{wf.get('total_workflows', 0)} ok",
              "items": [
                  {"id": w["id"][:8], "status": w["status"], "step": w["type"]}
                  for w in recent
              ],
          },
      }
  ```

**Test** `tests/test_workflow_pipeline_integration.py` (~120 satır, 4 test):

1. `test_pipeline_no_workflow_when_disabled`: `settings.workflow_durable=False`, `QualCodePipeline().run(...)` → `workflow_state.db` boş kalır.
2. `test_pipeline_writes_workflow_when_enabled`: `monkeypatch settings.workflow_durable=True` + `tmp_path data_dir`, sahte provider mock (cf+groq httpx mock), `run("...")` → `list_workflows(wf_type="qual-code")` 1 kayıt, en az 1 step.
3. `test_pipeline_finish_records_status_fail_on_error`: tüm provider'lar exception fırlatsın → workflow status `"fail"`.
4. `test_qual_human_chains_workflow`: `QualHumanPipeline` nested `QualTrPipeline` çağırır; iki ayrı workflow yazılmalı (parent + nested) **VEYA** tek parent workflow (kararı: tek parent — nested pipeline `wf_type` farklı, ama child wf-type yazmaz). Test: parent `qual-human` workflow yazıldı + child step'ler kayıtlı.

**Test** `tests/test_stream_real_data.py` (~40 satır, 1 test):

- `tracker.bump("ask_test")` × 5
- `_build_mcp_tools()` → `tools[0]["name"] == "ask_test"`, `count_24h == 5`
- `_build_budget()["workflow"]["summary"]` → "0/0 ok" (boş DB)

### B. MLX Provider (Apple Silicon)

**Yeni dosya** `app/providers/mlx.py` (~95 satır):

```python
"""MLX provider — Apple Silicon Neural Engine HTTP bridge.

SERVER quick.py::ask_mlx pattern. Bridge daemon ABS dışında çalışır
(M4'te `mlx_lm.server` veya custom MLX server, default port 11436).
ABS_MLX_URL boş ise non-transient ProviderError.
"""
from __future__ import annotations
import time
from typing import Any, Optional

import httpx

from app.config import settings
from .base import BaseProvider
from .schemas import ProviderError, ProviderResponse


class MLXProvider(BaseProvider):
    name = "mlx"
    default_model = "llama3-8b"
    default_timeout = 30.0

    async def call(self, prompt: str, model: Optional[str] = None, **kwargs: Any) -> ProviderResponse:
        if not settings.mlx_url:
            raise ProviderError(
                "MLX_URL tanımlı değil — Apple Silicon Neural Engine bridge yok",
                provider=self.name, transient=False,
            )
        model = model or self.default_model
        url = settings.mlx_url.rstrip("/") + "/v1/generate"
        body = {
            "model": model,
            "prompt": prompt,
            "max_tokens": kwargs.get("max_tokens", 1024),
        }
        timeout = kwargs.get("timeout", self.default_timeout)
        start = time.monotonic()
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                r = await client.post(url, json=body)
        except httpx.TimeoutException as exc:
            raise ProviderError(f"MLX timeout ({timeout}s)", provider=self.name, transient=True) from exc
        except httpx.HTTPError as exc:
            raise ProviderError(f"MLX bağlantı: {exc}", provider=self.name, transient=True) from exc

        elapsed_ms = int((time.monotonic() - start) * 1000)
        if r.status_code >= 400:
            raise ProviderError(
                f"MLX {r.status_code}: {r.text[:200]}",
                provider=self.name, transient=(r.status_code >= 500),
            )
        try:
            data = r.json()
        except ValueError as exc:
            raise ProviderError("MLX JSON parse", provider=self.name, transient=True) from exc

        text = data.get("response") or ""
        if not text and "error" in data:
            raise ProviderError(f"MLX: {data['error']}", provider=self.name, transient=True)

        return ProviderResponse(
            text=text, model=model, provider=self.name, elapsed_ms=elapsed_ms,
            tokens_in=data.get("prompt_tokens"),
            tokens_out=data.get("completion_tokens"),
        )
```

**Registry patch** `app/providers/registry.py`:
```python
from .mlx import MLXProvider
# ...
_registry["mlx"] = MLXProvider()
```

**MCP tools** — `app/mcp/tools/provider_extras.py` İÇİNE ekle (yeni dosya açma — `provider_extras` zaten 15 tool barındırıyor):
```python
@mcp_server.tool()
@with_hooks("ask_mlx")
async def ask_mlx(prompt: str) -> str:
    """MLX Neural Engine — Apple Silicon (M4) llama3-8b ~0.3-1s."""
    await tracker.bump("ask_mlx")
    return await _call("mlx", prompt, model="llama3-8b")

@mcp_server.tool()
@with_hooks("ask_mlx_fast")
async def ask_mlx_fast(prompt: str) -> str:
    """MLX Fast — phi3-mini ultra hızlı sınıflandırma <0.5s."""
    await tracker.bump("ask_mlx_fast")
    return await _call("mlx", prompt, model="phi3-mini")

REGISTERED_TOOLS.extend(["ask_mlx", "ask_mlx_fast"])
```

**Test** `tests/test_provider_mlx.py` (~80 satır, 3 test):

1. `test_mlx_no_url_raises_provider_error`: `settings.mlx_url=""` → `ProviderError(transient=False)`.
2. `test_mlx_success_response_parsed`: `respx` mock `POST /v1/generate` → `{"response":"hello","prompt_tokens":3,"completion_tokens":1}` → `ProviderResponse.text == "hello"`, `model == "llama3-8b"`.
3. `test_mlx_error_field_raises_transient`: mock `{"error":"OOM"}` → `ProviderError(transient=True)`.

### C. Judge Live Training (Persona Dynamic Adjust)

**Yeni dosya** `app/judge/training.py` (~140 satır):

Algoritma (basit, deterministik — overfit önleme):
1. `judge_log.jsonl` son N (default 200) entry oku
2. `outcome="accept"` olan entry'lerin `persona_drift` ortalamasını al → `accept_drift_avg`
3. `outcome="reject"` olan entry'lerin → `reject_drift_avg`
4. Eğer `reject_drift_avg > accept_drift_avg + 0.10` → persona threshold'lar **gevşesin** (kabul edilen kod hedefe daha uzak; mevcut hedef gerçekçi değil): `docstring_ratio -= 0.05`, `type_hints_ratio -= 0.05`
5. Eğer `accept_drift_avg < reject_drift_avg - 0.10` → persona threshold'lar **sertleşsin**: `docstring_ratio += 0.05`, `type_hints_ratio += 0.05`
6. Aralık clamp: docstring [0.30, 0.85], type_hints [0.40, 0.95]
7. Yeni persona `cache_dir/persona.json`'a yaz (atomic temp+rename)
8. Audit log: `cache_dir/persona_history.jsonl` append `{ts, before, after, sample_size, accept_avg, reject_avg, action: "tighten|loosen|stable"}`

```python
def train_persona(min_samples: int = 10, history_limit: int = 200) -> dict:
    """Live training: outcome'lara göre persona threshold'larını adapt et."""
    # ...
    return {
        "action": "tighten|loosen|stable|insufficient_data",
        "samples": int,
        "accept_drift_avg": float|None,
        "reject_drift_avg": float|None,
        "before": dict, "after": dict,
    }

def persona_status() -> dict:
    """Mevcut persona + son training tarihi + history özeti."""

def reset_persona() -> dict:
    """persona.json sil → DEFAULT_PERSONA'ya dön. history korunur."""
```

**MCP tools** — yeni dosya `app/mcp/tools/judge_persona.py` (~50 satır, 3 tool):

```python
@mcp_server.tool()
@with_hooks("judge_persona_status")
async def judge_persona_status() -> str:
    """Mevcut persona threshold'ları + son training meta."""
    await tracker.bump("judge_persona_status")
    return json.dumps(persona_status(), ensure_ascii=False, indent=2)

@mcp_server.tool()
@with_hooks("judge_persona_train")
async def judge_persona_train(min_samples: int = 10) -> str:
    """judge_log outcome'larından persona dynamic adjust. min_samples altında 'insufficient_data'."""
    await tracker.bump("judge_persona_train")
    return json.dumps(train_persona(min_samples=min_samples), ensure_ascii=False, indent=2)

@mcp_server.tool()
@with_hooks("judge_persona_reset")
async def judge_persona_reset() -> str:
    """Persona'yı DEFAULT_PERSONA'ya geri al (history dosyası korunur)."""
    await tracker.bump("judge_persona_reset")
    return json.dumps(reset_persona(), ensure_ascii=False, indent=2)

REGISTERED_TOOLS = ["judge_persona_status", "judge_persona_train", "judge_persona_reset"]
```

**Test** `tests/test_judge_persona_training.py` (~120 satır, 4 test):

1. `test_persona_train_insufficient_data`: judge_log boş → `action="insufficient_data"`, persona değişmez.
2. `test_persona_train_loosens_when_rejects_have_higher_drift`: 10 fake entry: 5 accept (drift=0.10), 5 reject (drift=0.30) → `action="loosen"`, `docstring_ratio` 0.60 → 0.55.
3. `test_persona_train_tightens_when_accepts_have_lower_drift`: tersi durum → `action="tighten"`, threshold 0.60 → 0.65.
4. `test_persona_reset_restores_default`: train ile threshold değiştir → `reset_persona()` → `load_persona() == DEFAULT_PERSONA`. `cache_dir/persona_history.jsonl` korunur.

### D. RAG Semantic Chunk-Split

**Yeni dosya** `app/rag/chunker.py` (~140 satır):

```python
"""AST-aware chunker. Python: function/class boundary, MD: heading-based, fallback char-split."""
from __future__ import annotations
import ast
import re
from pathlib import Path
from typing import Iterable, Tuple

_CHAR_FALLBACK = 1500

def chunk_python(text: str) -> Iterable[Tuple[int, str]]:
    """Top-level def/class boundary'lerinde böl. Boundary dışı kod 'preamble' olur."""
    try:
        tree = ast.parse(text)
    except SyntaxError:
        yield from chunk_chars(text)
        return
    boundaries = sorted(
        n.lineno for n in tree.body
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
    )
    if not boundaries:
        yield from chunk_chars(text)
        return
    lines = text.splitlines(keepends=True)
    boundaries = [1] + boundaries + [len(lines) + 1]
    idx = 0
    for start, end in zip(boundaries, boundaries[1:]):
        chunk = "".join(lines[start - 1 : end - 1]).strip()
        if chunk:
            yield idx, chunk
            idx += 1

_MD_HEADING = re.compile(r"^#{1,6}\s", re.MULTILINE)

def chunk_markdown(text: str) -> Iterable[Tuple[int, str]]:
    """Heading bazlı bölme. Heading yoksa char-fallback."""
    matches = list(_MD_HEADING.finditer(text))
    if not matches:
        yield from chunk_chars(text)
        return
    boundaries = [m.start() for m in matches] + [len(text)]
    idx = 0
    if boundaries[0] > 0:
        preamble = text[: boundaries[0]].strip()
        if preamble:
            yield idx, preamble
            idx += 1
    for start, end in zip(boundaries, boundaries[1:]):
        section = text[start:end].strip()
        if section:
            yield idx, section
            idx += 1

def chunk_chars(text: str, size: int = _CHAR_FALLBACK) -> Iterable[Tuple[int, str]]:
    for i, start in enumerate(range(0, len(text), size)):
        yield i, text[start : start + size]

def chunk_for_path(path: Path, text: str, strategy: str = "semantic") -> Iterable[Tuple[int, str]]:
    if strategy == "char":
        yield from chunk_chars(text)
        return
    suf = path.suffix.lower()
    if suf == ".py":
        yield from chunk_python(text)
    elif suf in (".md", ".mdx"):
        yield from chunk_markdown(text)
    else:
        yield from chunk_chars(text)
```

**Patch** `app/rag/indexer.py` `index_path`:
- Yeni parametre: `chunk_strategy: str = "semantic"`
- `for idx, chunk in _chunk_iter(text):` yerine: `from .chunker import chunk_for_path; for idx, chunk in chunk_for_path(fp, text, chunk_strategy):`
- Skip-if-too-large: chunk > 8000 char ise char-fallback (Python tek dev fonksiyon edge case).

**Patch** `app/mcp/tools/rag.py` `rag_index`:
```python
async def rag_index(path: str, project: str = "default", chunk_strategy: str = "semantic") -> str:
    ...
    res = await _index_path(path, project=project, chunk_strategy=chunk_strategy)
```

**Test** `tests/test_rag_chunker.py` (~140 satır, 4 test):

1. `test_python_chunks_split_at_function_boundary`: 3 fonksiyonlu Python source → 4 chunk (preamble + 3 fonksiyon) veya 3 (preamble boş).
2. `test_markdown_chunks_split_at_headings`: `# A\n...\n## B\n...\n# C\n...` → 3 chunk (her heading'den).
3. `test_unknown_extension_falls_back_to_chars`: `.txt` 3000 char → 2 chunk.
4. `test_invalid_python_falls_back_gracefully`: `def broken(:` syntax-error → char-split fallback, exception fırlatmaz.

### E. Dockerfile + pyproject.toml Patch

**`pyproject.toml` patch:**
```toml
dependencies = [
    # ...mevcut...
    "anthropic>=0.40",
    "cohere>=5.13",          # 008'de venv'e kuruldu, pyproject.toml'a yazılmamıştı
    "chromadb>=0.4.22",      # 009'da venv'e kuruldu, pyproject.toml'a yazılmamıştı
]
```

**`Dockerfile` patch** (multi-stage, build deps yalnız builder'da):
```dockerfile
FROM python:3.11-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app

FROM base AS builder
# chromadb rust binding + senin patch_engine için patch binary
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ libsqlite3-dev patch \
    && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml ./
COPY app/ ./app/
RUN pip install --prefix=/install .

FROM base AS runtime
# runtime'da sadece patch binary lazım (apply_patch tool çalışsın)
RUN apt-get update && apt-get install -y --no-install-recommends patch \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /install /usr/local
COPY app/ ./app/
RUN mkdir -p /app/data && \
    useradd --create-home --uid 1000 abs && \
    chown -R abs:abs /app
USER abs

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Smoke (Worker yapsın):**
```bash
cd /Users/eneseserkan/Main/abs-server-product
docker compose -f infra/docker-compose.yml build backend
# Build başarılı + image boyutu ~250-400MB
```

Eğer build başarısız (CI yok): `summary.md`'de "build smoke skip — local docker yok" yaz.

### F. Registry + Test Count

**`app/mcp/server.py` patch** — `register_all_tools()`:
- `from app.mcp.tools import judge_persona  # noqa: F401  (010)` import ekle
- `+ len(judge_persona.REGISTERED_TOOLS)` count ekle
- `provider_extras.REGISTERED_TOOLS` 17 olur (15 + ask_mlx + ask_mlx_fast) — listenin uzaması doğal.
- `Write` ile **tam override** kullan (Edit 008/009'da 3x atlandı).

**`tests/test_tools_count.py` patch:**
```python
def test_registered_tool_count_at_least_89():
    assert len(tools) >= 89, f"Tool sayısı düştü: {len(tools)}"

# must_have ekle:
"ask_mlx", "ask_mlx_fast",
"judge_persona_status", "judge_persona_train", "judge_persona_reset",
```

## Kısıtlar

- **Python 3.11+**, FastMCP `@mcp_server.tool()` + `@with_hooks(name)` + `await tracker.bump(name)` üçlüsü her yeni tool'a.
- **`workflow_durable` default `False`** — opt-in. Test sırasında `monkeypatch settings.workflow_durable=True`.
- **MLX testleri offline çalışsın** — `respx` ile httpx mock. Gerçek MLX bridge testte aranmaz.
- **`chunk_for_path` exception-free olmalı** — invalid Python parse → char-fallback (assertion: hiç raise etme).
- **Persona training idempotent** — aynı log girdileriyle 2 kere train çağrısı aynı sonucu üretmeli (`stable` ikinci çağrıda eğer 1. çağrı sonrası avg değişmediyse).
- **Dockerfile builder/runtime ayrı** — `gcc/g++/libsqlite3-dev` runtime'da olmasın (image küçük kalsın). `patch` runtime'da gerekli.
- **SSE patch panel'i bozmasın** — testte `_build_mcp_tools()` snapshot boşken `[]` dönmeli (random tablo yerine boş kabul edilir).
- **Freeze AKTIF**: tüm dosya işlemleri `/Users/eneseserkan/Main/abs-server-product` içinde. SERVER referans olarak READ-ONLY (Edit/Write yok).
- **pytest 134/134** zorunlu. Bir test bile fail bırakma.

## Adımlar (Worker Claude için)

### 1. Önkoşul + giriş doğrulama (5 dk)
```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                 # 118 passed
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 84
```

### 2. Modul A — Workflow×Pipeline (45 dk)
1. `app/config.py` → `workflow_durable` + `mlx_url` ekle
2. `app/workflow/integration.py` (yukarıdaki şablon)
3. 6 pipeline patch sırayla: `quality/{code,turkish,analysis,translate}.py`, `humanize/{qual_human,qual_code_human}.py`. Her birinde:
   - `from app.workflow.integration import WorkflowSession`
   - `wf = WorkflowSession(self.pipeline_type, prompt)` run başında
   - Her step append'inden sonra `wf.step(...)`
   - `return PipelineResult(...)` öncesi `wf.finish("ok" if not error else "fail")`
4. `app/api/stream.py` patch: `_build_mcp_tools` + `_build_budget` real
5. `tests/test_workflow_pipeline_integration.py` (4 test) + `tests/test_stream_real_data.py` (1 test)
6. `pytest tests/test_workflow_pipeline_integration.py tests/test_stream_real_data.py -v` → 5 PASS

### 3. Modul B — MLX Provider (30 dk)
1. `app/providers/mlx.py` (yukarıdaki şablon)
2. `app/providers/registry.py` patch (Write tam override)
3. `app/mcp/tools/provider_extras.py` İÇİNE `ask_mlx` + `ask_mlx_fast` ekle (REGISTERED_TOOLS extend)
4. `tests/test_provider_mlx.py` (3 test, respx mock)
5. `pytest tests/test_provider_mlx.py -v` → 3 PASS

### 4. Modul C — Judge Live Training (45 dk)
1. SERVER'da `judge_persona.py` veya benzeri varsa Read (`/Users/eneseserkan/Main/Automatia BCN/SERVER/orchestrator/`'da `grep -l persona`) — yoksa şablonla yaz
2. `app/judge/training.py` (algoritma yukarıda)
3. `app/judge/persona.py` patch — `load_persona()` zaten cache'den okuyor; persona.json training tarafından güncellenince load otomatik yansır
4. `app/mcp/tools/judge_persona.py` (3 tool)
5. `tests/test_judge_persona_training.py` (4 test, fake JSONL writer)
6. `pytest tests/test_judge_persona_training.py -v` → 4 PASS

### 5. Modul D — RAG Semantic Chunker (30 dk)
1. `app/rag/chunker.py` (yukarıdaki şablon)
2. `app/rag/indexer.py` patch — `index_path` `chunk_strategy` parametresi, `chunk_for_path` çağırsın
3. `app/mcp/tools/rag.py` patch — `rag_index` `chunk_strategy` parametresi
4. `tests/test_rag_chunker.py` (4 test) — Chroma'sız; sadece chunker fonksiyonları
5. `pytest tests/test_rag_chunker.py -v` → 4 PASS

### 6. Modul E — Registry + Test Count (15 dk)
1. `app/mcp/server.py` Read → tam Write override (`judge_persona` import + count + 010 yorumu)
2. `tests/test_tools_count.py` patch (84 → 89, must_have'a 5 yeni tool)
3. `pytest tests/test_tools_count.py -v` → 2 PASS

### 7. Modul F — Dockerfile + pyproject.toml (10 dk)
1. `pyproject.toml` `dependencies` listesine `cohere>=5.13`, `chromadb>=0.4.22` ekle
2. `Dockerfile` Write tam override (yukarıdaki şablon)
3. (opsiyonel) `docker compose build backend` smoke

### 8. Tam Test Suite (5 dk)
```bash
.venv/bin/pytest -q
# 134+ passed beklenir
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 89
```

### 9. Live MCP Smoke (10 dk)
```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/uvicorn app.main:app --port 8765 &
# claude mcp add abs-010 http://localhost:8765/mcp/ --transport http
# claude mcp list  → "abs-010 ✓ Connected, 89 tools"
```
4 canlı tool kanıtı (her biri valid JSON dönsün):
- `judge_persona_status` → `{"persona": {...}, "history_size": 0, ...}`
- `ask_mlx_fast("test")` → `[HATA] MLX_URL tanımlı değil` (graceful — bridge yok normal)
- `rag_index("/tmp", "test", "semantic")` → `{"indexed": N, ...}` (Ollama yoksa skipped)
- `workflow_status()` → `{"total_workflows": 0, ...}` (boş DB)

(MLX live test M4'te `mlx_lm.server` ayrıca açıksa: `ABS_MLX_URL=http://localhost:11436 .venv/bin/uvicorn ... && tool ask_mlx("hi")` real response. Yoksa graceful kanıt yeterli.)

### 10. Tamamlama
1. `_agent-tasks/completed/010-pipeline-mlx-judge-train.md` → bu dosyayı taşı
2. `_agent-tasks/completed/010-pipeline-mlx-judge-train-summary.md` yaz:
   - 5 modül her biri ne yapıldı (dosya listesi + satır sayıları)
   - Delegation kullanımı (kalite pipeline, hangi MCP, neden)
   - Atlanan/blocker (varsa)
   - Test sonuçları (118 → 134+)
   - Live MCP smoke (4 tool JSON kanıtı)
   - Notlar Planlayıcıya

## Doğrulama (Worker bunu fail-fast koşacak)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pip install -e .                                   # cohere + chromadb pyproject'ten geri kuruluyor
.venv/bin/pytest -q                                          # >= 134 passed
.venv/bin/pytest tests/test_tools_count.py -v                # 89 guard
.venv/bin/python -c "from app.mcp.server import mcp_server; import asyncio; print(len(asyncio.run(mcp_server.list_tools())))"
# 89
.venv/bin/python -c "from app.workflow import stats; print(stats())"
# {'total_workflows': 0, ...}
.venv/bin/python -c "from app.judge.training import persona_status; print(persona_status())"
# {'persona': {...}, 'history_size': 0, ...}
```

Hepsi yeşil değilse: **task completed işaretleme**. Worker hangi adımda takıldıysa `summary.md`'de açık yaz.

## Notlar Planlayıcıya (raporda doldur)

- Workflow integration `qual_*` 4 + `qual_*_human` 2 = 6 pipeline; race/verify pipeline'lara WorkflowSession **eklendi mi atlandı mı**? (Önerim: race FIRST_COMPLETED kazanan tek sonuç → workflow değer azaldı, atla. Verify Ollama tek-step → yine atla. 6 yeterli.)
- MLX provider Docker imajına eklendi mi? (Beklenti: Hayır — MLX sadece M4 host'ta çalışır, Docker'da `mlx_url` boş kalır. Docker müşteri için runtime opt-in.)
- Persona training algoritması (drift karşılaştırma) çok basit. 011/012'de gradient-based veya ML-tabanlı (logistic regression on outcome) alternatif düşünülebilir. Şimdilik deterministik + idempotent yeterli.
- RAG chunk_strategy default `"semantic"` yapıldı — eski indexlenmiş chunk'lar hâlâ char-split formatta. Migration opsiyonu (re-index önerisi) `summary.md`'de panel notu olarak gel.
- SSE `_build_budget` `today_usd` ve `learnings_count` placeholder kalmaya devam — gerçek bütçe + learnings tracker 011'e (Anthropic API usage feed + learnings JSONL feed).
- Cohere `track_usage` 008'de pyproject.toml'a yazılmamış olması **regresyon riski**: 010 öncesi `pip install -e .` çalıştırıldığında cohere kurulmadan testler yeşil görünüyordu (cohere lazy import). Düzeltme: pyproject + Dockerfile patch zorunlu.

## Feature Parity Kuralı (HATIRLATMA)

010 yeni yetenek ekler — SERVER'dan port DEĞİL. SERVER'da MLX `quick.py` içinde inline; persona training henüz yok (live training ABS-only innovation); RAG semantic split SERVER'da yarım. Bu task SERVER paritesinden ileriye geçer. Atlanan parity yok.

## Kapsam Dışı (011+'a)

- Update channel + watchdog (`docs/operations.md`'de plan, ayrı task)
- Cache hit counter real implementation (cache_stats şu an dummy 0/0)
- Multi-tenant cache prefix (tenant_id)
- Anthropic budget tracker (real `today_usd` SSE feed)
- ML-based persona training (logistic regression outcome predictor)
- RAG hybrid (BM25 + cosine)
- Symbol graph real (`/api/symbol_graph` placeholder)
- Encryption AES-256 profile (E13.5)
