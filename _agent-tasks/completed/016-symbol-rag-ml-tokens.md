# Task 016 — Symbol Graph + RAG Hybrid + ML Persona Training v2 + Real Token Tracking

**Tahmini süre:** 4 saat (4 modül + 3 yeni MCP tool + tracker schema migration)
**Önkoşul:** 015 tamam (99 MCP tool, 247 passed + 2 skipped)

## Bağlam

015 sonrası ABS production-ready. Kalan 4 inovasyon parçası — müşteri için "nice-to-have" ama ürünü farklılaştıran katmanlar:

1. **Symbol Graph stub** (`/api/symbol-graph/*`) — şu an boş `[]` döndürüyor. Python AST parser ile def/class/import edge graph
2. **RAG sadece cosine** (009/010) — BM25 keyword reranking yok. SERVER'da `query_hybrid` pattern (rag.py:625) port edilecek
3. **Judge persona training v1 deterministik** (010) — `±0.05 step` simple drift heuristic. ML alternatifi: outcome (accept/reject) → logistic regression predictor
4. **Tracker token sayısı yok** — 015 cost estimator avg 1500 token varsayımı. `tracker.bump(name, tokens_in=N, tokens_out=M)` schema upgrade

**Tool sayısı hedefi:** 99 → **102 tool** (+3: `symbol_search`, `rag_hybrid`, `judge_persona_predict`).
**Test sayısı hedefi:** 247 → **~268+ test** (+21: 5 symbol AST, 5 rag hybrid, 4 ml persona, 4 token tracking, 3 mcp).

## Giriş

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                       # 247 + 2 skipped
.venv/bin/python -c "from app.api.symbol_graph import router; print([r.path for r in router.routes])"
# /api/symbol-graph/neighbors (stub)
.venv/bin/python -c "from app.mcp.tracking import tracker; help(tracker.bump)"
# bump(tool_name) — tokens parametresi yok
ls app/judge/                                             # training.py (010), persona.py
ls app/rag/                                               # query.py (sadece cosine), indexer.py
```

**Yeni dosyalar (016):**
- `app/symbols/__init__.py` + `app/symbols/parser.py` + `app/symbols/store.py` + `app/symbols/index.py`
- `app/rag/hybrid.py` — BM25 + cosine reranker
- `app/judge/ml_persona.py` — logistic regression outcome predictor (scikit-learn opsiyonel; saf numpy + manual gradient descent fallback)
- `app/mcp/tools/innovation_tools.py` — 3 yeni tool

**Patch'lenecek:**
- `app/api/symbol_graph.py` — gerçek implementation (5 endpoint)
- `app/mcp/tracking.py::UsageTracker.bump` — `tokens_in`/`tokens_out` parametreleri
- `app/billing/cost_estimator.py` — gerçek token sayısı kullan (avg fallback geriye dönük uyumlu)
- `app/rag/query.py` — `query_hybrid` çağrı sarmalayıcısı opsiyonel
- `app/judge/training.py` — `train_persona_ml` alternatif method
- `app/cascade/orchestrator.py` — başarılı çağrı sonrası `tracker.bump(name, tokens_in=resp.tokens_in, tokens_out=resp.tokens_out)`
- `app/pipelines/quality/code.py` + `tr.py` + `analysis.py` + `translate.py` — pipeline çağrılarında token forward
- `app/mcp/server.py` — innovation_tools register
- `tests/test_tools_count.py` — 99 → 102 + 3 must_have

## Beklenen Çıktı

### A. Symbol Graph Real (Python AST)

**Yeni dosya** `app/symbols/parser.py` (~150 satır):

```python
"""Python AST parser — fonksiyon/class/import sembolleri ve aralarındaki edge'ler."""
from __future__ import annotations
import ast
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, List, Optional

logger = logging.getLogger(__name__)


@dataclass
class Symbol:
    name: str
    kind: str               # function | class | import
    file: str
    lineno: int
    parent: Optional[str] = None
    edges_out: List[str] = field(default_factory=list)


def parse_python_file(path: Path) -> List[Symbol]:
    """Tek bir .py dosyasından sembolleri çıkar."""
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return []
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return []
    symbols: List[Symbol] = []

    class _V(ast.NodeVisitor):
        def __init__(self):
            self.parent_stack: List[str] = []

        def visit_FunctionDef(self, node):
            full = ".".join(self.parent_stack + [node.name])
            sym = Symbol(name=full, kind="function", file=str(path), lineno=node.lineno,
                        parent=".".join(self.parent_stack) or None)
            sym.edges_out = sorted(set(self._extract_calls(node)))
            symbols.append(sym)
            self.parent_stack.append(node.name)
            self.generic_visit(node)
            self.parent_stack.pop()

        visit_AsyncFunctionDef = visit_FunctionDef

        def visit_ClassDef(self, node):
            full = ".".join(self.parent_stack + [node.name])
            symbols.append(Symbol(name=full, kind="class", file=str(path),
                                  lineno=node.lineno, parent=".".join(self.parent_stack) or None))
            self.parent_stack.append(node.name)
            self.generic_visit(node)
            self.parent_stack.pop()

        def visit_Import(self, node):
            for alias in node.names:
                symbols.append(Symbol(name=alias.name, kind="import",
                                      file=str(path), lineno=node.lineno))

        def visit_ImportFrom(self, node):
            mod = node.module or ""
            for alias in node.names:
                full = f"{mod}.{alias.name}" if mod else alias.name
                symbols.append(Symbol(name=full, kind="import",
                                      file=str(path), lineno=node.lineno))

        def _extract_calls(self, fn_node):
            calls = []
            for n in ast.walk(fn_node):
                if isinstance(n, ast.Call):
                    if isinstance(n.func, ast.Name):
                        calls.append(n.func.id)
                    elif isinstance(n.func, ast.Attribute):
                        calls.append(n.func.attr)
            return calls

    _V().visit(tree)
    return symbols


def parse_directory(root: Path, skip_dirs: Optional[set] = None) -> List[Symbol]:
    skip = skip_dirs or {"node_modules", ".git", ".venv", "venv", "__pycache__", "dist", "build"}
    out: List[Symbol] = []
    import os
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip and not d.startswith(".")]
        for fn in filenames:
            if fn.endswith(".py"):
                out.extend(parse_python_file(Path(dirpath) / fn))
    return out
```

**Yeni dosya** `app/symbols/store.py` (~110 satır) — SQLite persist:

```python
"""Symbol store — SQLite tablosu (symbols + edges)."""
from __future__ import annotations
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import List
from app.config import settings
from .parser import Symbol


def _db_path() -> Path:
    p = Path(settings.data_dir) / "symbols.db"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


@contextmanager
def _connect():
    conn = sqlite3.connect(str(_db_path()), timeout=10.0)
    conn.row_factory = sqlite3.Row
    try:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS symbols (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            file TEXT NOT NULL,
            lineno INTEGER NOT NULL,
            parent TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name);
        CREATE INDEX IF NOT EXISTS idx_symbols_kind ON symbols(kind);
        CREATE TABLE IF NOT EXISTS edges (
            from_sym TEXT NOT NULL,
            to_sym TEXT NOT NULL,
            file TEXT NOT NULL,
            UNIQUE(from_sym, to_sym, file)
        );
        CREATE INDEX IF NOT EXISTS idx_edges_from ON edges(from_sym);
        CREATE INDEX IF NOT EXISTS idx_edges_to ON edges(to_sym);
        """)
        yield conn
        conn.commit()
    finally:
        conn.close()


def reset() -> None:
    p = _db_path()
    if p.is_file():
        p.unlink()


def bulk_insert(symbols: List[Symbol]) -> int:
    if not symbols:
        return 0
    with _connect() as conn:
        cur = conn.executemany(
            "INSERT INTO symbols (name, kind, file, lineno, parent) VALUES (?, ?, ?, ?, ?)",
            [(s.name, s.kind, s.file, s.lineno, s.parent) for s in symbols],
        )
        edge_rows = [(s.name, e, s.file) for s in symbols for e in s.edges_out]
        if edge_rows:
            conn.executemany(
                "INSERT OR IGNORE INTO edges (from_sym, to_sym, file) VALUES (?, ?, ?)",
                edge_rows,
            )
        return cur.rowcount


def search(name_substr: str, limit: int = 20, kind: str | None = None) -> List[dict]:
    sql = "SELECT name, kind, file, lineno FROM symbols WHERE name LIKE ?"
    params = [f"%{name_substr}%"]
    if kind:
        sql += " AND kind = ?"
        params.append(kind)
    sql += " ORDER BY name LIMIT ?"
    params.append(limit)
    with _connect() as conn:
        rows = conn.execute(sql, params).fetchall()
    return [dict(r) for r in rows]


def neighbors(name: str, depth: int = 1) -> dict:
    """Verilen sembol etrafında BFS depth-N graph."""
    with _connect() as conn:
        sym = conn.execute(
            "SELECT * FROM symbols WHERE name = ? LIMIT 1", (name,)
        ).fetchone()
        if not sym:
            return {"status": "not_found", "name": name}
        visited = {name}
        edges_collected = []
        frontier = {name}
        for _ in range(depth):
            new_frontier = set()
            for f in frontier:
                rows = conn.execute(
                    "SELECT to_sym, file FROM edges WHERE from_sym = ? UNION "
                    "SELECT from_sym, file FROM edges WHERE to_sym = ?",
                    (f, f),
                ).fetchall()
                for r in rows:
                    other = r["to_sym"] if r["to_sym"] != f else r["from_sym"]
                    edges_collected.append({"from": f, "to": other, "file": r["file"]})
                    if other not in visited:
                        visited.add(other)
                        new_frontier.add(other)
            frontier = new_frontier
        return {
            "status": "ok",
            "root": dict(sym),
            "depth": depth,
            "neighbors": [{"name": n} for n in visited - {name}],
            "edges": edges_collected[:200],
            "total_visited": len(visited),
        }


def stats() -> dict:
    with _connect() as conn:
        total = conn.execute("SELECT COUNT(*) AS c FROM symbols").fetchone()["c"]
        edges = conn.execute("SELECT COUNT(*) AS c FROM edges").fetchone()["c"]
        by_kind = {r["kind"]: r["c"] for r in conn.execute(
            "SELECT kind, COUNT(*) c FROM symbols GROUP BY kind"
        )}
    return {"total_symbols": total, "total_edges": edges, "by_kind": by_kind}
```

**Yeni dosya** `app/symbols/index.py` (~50 satır):

```python
"""Index orchestrator — parse_directory + store.bulk_insert."""
from __future__ import annotations
from pathlib import Path
from .parser import parse_directory
from .store import bulk_insert, reset, stats as store_stats


def index_path(path: str, replace: bool = False) -> dict:
    p = Path(path)
    if not p.exists():
        return {"error": f"yol yok: {path}", "indexed": 0}
    if replace:
        reset()
    syms = parse_directory(p)
    inserted = bulk_insert(syms)
    return {"path": str(p), "indexed": inserted, "stats": store_stats()}
```

**Patch** `app/api/symbol_graph.py` — gerçek implementation:

```python
@router.get("/neighbors")
async def get_neighbors(name: str = Query(...), depth: int = Query(1, ge=1, le=5),
                        _admin: dict = Depends(current_admin)) -> dict:
    from app.symbols.store import neighbors
    return neighbors(name, depth=depth)


@router.get("/search")
async def search_symbols(q: str = Query(..., min_length=1),
                         kind: str | None = Query(None),
                         _admin: dict = Depends(current_admin)) -> dict:
    from app.symbols.store import search
    return {"query": q, "results": search(q, kind=kind, limit=50)}


@router.get("/stats")
async def get_stats(_admin: dict = Depends(current_admin)) -> dict:
    from app.symbols.store import stats
    return stats()


@router.post("/index")
async def post_index(body: dict, _admin: dict = Depends(current_admin)) -> dict:
    from app.symbols.index import index_path
    return index_path(body.get("path", "."), replace=bool(body.get("replace", False)))
```

**Test** `tests/test_symbols_parser.py` (~140 satır, 5 test):

1. `test_parse_python_file_extracts_functions`: tmp_path with `def foo(): pass\nasync def bar(): pass` → 2 symbols, kinds function.
2. `test_parse_class_with_methods`: nested class+def → 3 symbols (class + 2 methods), parent set.
3. `test_parse_imports`: `import os\nfrom pathlib import Path` → 2 import symbols.
4. `test_neighbors_depth_1`: 2 fonksiyon birbirini çağırıyor → neighbors(A, depth=1) içinde B var.
5. `test_search_substring_match`: store.search("calc") → eşleşen tüm symbol'ler.

### B. RAG Hybrid (BM25 + Cosine)

**Yeni dosya** `app/rag/hybrid.py` (~140 satır):

```python
"""RAG hybrid retrieval — BM25 keyword + cosine semantic, weighted fusion."""
from __future__ import annotations
import math
import re
from collections import Counter
from typing import Any, Dict, List, Optional
from app.rag.indexer import _collection
from app.rag import embedding as _emb


_TOKEN_RE = re.compile(r"\w+")


def _tokenize(text: str) -> List[str]:
    return [t.lower() for t in _TOKEN_RE.findall(text)]


def _bm25_score(query_tokens: List[str], doc_tokens: List[str],
                avg_dl: float, doc_freqs: Dict[str, int], n_docs: int,
                k1: float = 1.5, b: float = 0.75) -> float:
    """Klasik BM25."""
    score = 0.0
    dl = len(doc_tokens)
    tf = Counter(doc_tokens)
    for q in query_tokens:
        if q not in doc_freqs:
            continue
        df = doc_freqs[q]
        idf = math.log((n_docs - df + 0.5) / (df + 0.5) + 1.0)
        f = tf.get(q, 0)
        denom = f + k1 * (1 - b + b * dl / max(avg_dl, 1.0))
        if denom > 0:
            score += idf * (f * (k1 + 1)) / denom
    return score


async def query_hybrid(question: str,
                       project_filter: Optional[str] = None,
                       top_k: int = 5,
                       alpha_semantic: float = 0.6) -> List[Dict[str, Any]]:
    """Cosine ile geniş havuz çek (top 30), BM25 ile yeniden sırala, fusion ile top_k."""
    if not question.strip():
        return []
    try:
        vec = await _emb.embed(question)
    except Exception as exc:
        return [{"error": f"embed fail: {exc}"}]
    coll = _collection()
    where = {"project": project_filter} if project_filter else None
    pool_size = max(top_k * 6, 30)
    try:
        result = coll.query(query_embeddings=[vec], n_results=pool_size, where=where)
    except Exception as exc:
        return [{"error": f"chroma query fail: {exc}"}]
    docs = (result.get("documents") or [[]])[0]
    metas = (result.get("metadatas") or [[]])[0]
    dists = (result.get("distances") or [[]])[0]
    if not docs:
        return []
    # BM25 corpus stats
    tokenized = [_tokenize(d) for d in docs]
    avg_dl = sum(len(t) for t in tokenized) / max(len(tokenized), 1)
    doc_freqs: Dict[str, int] = {}
    for toks in tokenized:
        for tok in set(toks):
            doc_freqs[tok] = doc_freqs.get(tok, 0) + 1
    q_toks = _tokenize(question)
    bm25_scores = [_bm25_score(q_toks, t, avg_dl, doc_freqs, len(docs)) for t in tokenized]
    cosine_scores = [1.0 - float(d) if d is not None else 0.0 for d in dists]
    # Min-max normalize
    def _norm(arr):
        mn, mx = min(arr), max(arr)
        if mx == mn:
            return [0.0 for _ in arr]
        return [(x - mn) / (mx - mn) for x in arr]
    bm25_n = _norm(bm25_scores)
    cos_n = _norm(cosine_scores)
    fused = [(alpha_semantic * c + (1 - alpha_semantic) * b)
             for c, b in zip(cos_n, bm25_n)]
    indexed = sorted(enumerate(fused), key=lambda x: -x[1])[:top_k]
    out = []
    for idx, score in indexed:
        out.append({
            "file": (metas[idx] or {}).get("file"),
            "project": (metas[idx] or {}).get("project"),
            "snippet": (docs[idx] or "")[:220],
            "score": round(score, 4),
            "bm25": round(bm25_scores[idx], 3),
            "cosine": round(cosine_scores[idx], 3),
        })
    return out
```

**Test** `tests/test_rag_hybrid.py` (~120 satır, 5 test):

1. `test_tokenize_basic`: `_tokenize("Hello, World!")` → `["hello", "world"]`.
2. `test_bm25_higher_for_keyword_match`: 2 doc, 1 keyword içerir → BM25 farkı pozitif.
3. `test_query_hybrid_empty_question`: `""` → `[]`.
4. `test_query_hybrid_uses_both_signals` (mocked Chroma + embedding): fused score formula doğru.
5. `test_alpha_zero_pure_bm25` (alpha=0): sıralama sadece BM25'ten gelsin.

### C. ML Persona Training v2 (Logistic Regression)

**Yeni dosya** `app/judge/ml_persona.py` (~160 satır):

```python
"""ML-based persona training — outcome (accept=1, reject=0) → logistic regression.

Feature: judgment'ın AST + LLM + persona_drift skoru. Model: 3-feature logistic.
Sklearn opsiyonel; yoksa numpy ile manuel gradient descent (basit, deterministik).
"""
from __future__ import annotations
import json
import logging
import math
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from app.config import settings
from app.judge.log import read_recent

logger = logging.getLogger(__name__)


def _model_path() -> Path:
    p = Path(settings.cache_dir) / "persona_ml_model.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def _extract_features(entry: dict) -> Optional[List[float]]:
    """3-feature: ast_score (0-10), llm_score (0-10), persona_drift (0-2)."""
    ast = entry.get("ast_score")
    llm = entry.get("llm_score")
    drift = entry.get("persona_drift")
    if ast is None or llm is None or drift is None:
        return None
    return [float(ast), float(llm), float(drift)]


def _sigmoid(x: float) -> float:
    if x >= 0:
        z = math.exp(-x)
        return 1.0 / (1.0 + z)
    z = math.exp(x)
    return z / (1.0 + z)


def _train_logistic(X: List[List[float]], y: List[int],
                    epochs: int = 200, lr: float = 0.05) -> Dict:
    """Basit gradient descent logistic regression. 3 feature, n samples."""
    n_features = len(X[0])
    w = [0.0] * n_features
    b = 0.0
    n = len(X)
    for _ in range(epochs):
        dw = [0.0] * n_features
        db = 0.0
        for xi, yi in zip(X, y):
            z = sum(wi * xij for wi, xij in zip(w, xi)) + b
            p = _sigmoid(z)
            err = p - yi
            for j in range(n_features):
                dw[j] += err * xi[j]
            db += err
        for j in range(n_features):
            w[j] -= lr * dw[j] / n
        b -= lr * db / n
    return {"weights": w, "bias": b, "n_samples": n}


def train_ml(min_samples: int = 20) -> Dict:
    entries = read_recent(limit=2000)
    rows = [(e, _extract_features(e), e.get("outcome")) for e in entries]
    rows = [(e, f, o) for e, f, o in rows if f and o in ("accept", "reject")]
    if len(rows) < min_samples:
        return {"action": "insufficient_data", "samples": len(rows),
                "min_required": min_samples}
    X = [r[1] for r in rows]
    y = [1 if r[2] == "accept" else 0 for r in rows]
    model = _train_logistic(X, y)
    payload = {
        "trained_at": time.time(),
        "weights": model["weights"],
        "bias": model["bias"],
        "n_samples": model["n_samples"],
        "feature_names": ["ast_score", "llm_score", "persona_drift"],
    }
    _model_path().write_text(json.dumps(payload), encoding="utf-8")
    return {"action": "trained", **payload}


def predict_accept(ast_score: float, llm_score: float, persona_drift: float) -> Dict:
    """Modeli yükleyip accept olasılığı döndür."""
    p = _model_path()
    if not p.is_file():
        return {"error": "model not trained yet — call train_ml first"}
    try:
        m = json.loads(p.read_text(encoding="utf-8"))
    except Exception as exc:
        return {"error": str(exc)}
    feats = [ast_score, llm_score, persona_drift]
    z = sum(w * x for w, x in zip(m["weights"], feats)) + m["bias"]
    prob = _sigmoid(z)
    return {
        "p_accept": round(prob, 4),
        "decision": "accept" if prob >= 0.5 else "reject",
        "model_n_samples": m.get("n_samples"),
    }


def model_status() -> Dict:
    p = _model_path()
    if not p.is_file():
        return {"trained": False}
    try:
        m = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {"trained": False, "error": "model corrupt"}
    return {"trained": True, "trained_at": m.get("trained_at"),
            "n_samples": m.get("n_samples"),
            "feature_names": m.get("feature_names", [])}
```

**Test** `tests/test_judge_ml_persona.py` (~120 satır, 4 test):

1. `test_train_insufficient_data`: <20 samples → `action="insufficient_data"`.
2. `test_train_with_sufficient_samples`: 25 fake entries (10 accept skor=8/8/0.1, 15 reject skor=4/4/0.5) → trained, model file yazıldı.
3. `test_predict_high_score_accepts`: train sonrası `predict(8.5, 8.0, 0.1)` → `decision=="accept"`, `p_accept>0.5`.
4. `test_predict_low_score_rejects`: `predict(2.0, 2.0, 1.0)` → `decision=="reject"`.

### D. Real Token Tracking

**Patch** `app/mcp/tracking.py::UsageTracker.bump`:

```python
@dataclass
class ToolUsage:
    count_total: int = 0
    count_24h: int = 0
    last_called_at: float = 0.0
    recent_calls: List[float] = field(default_factory=list)
    # 016 — token aggregation
    tokens_in_24h: int = 0
    tokens_out_24h: int = 0


class UsageTracker:
    async def bump(self, tool_name: str, *, tokens_in: int = 0, tokens_out: int = 0) -> None:
        # ... mevcut sürüm sonuna ekle:
        u.tokens_in_24h += int(tokens_in)
        u.tokens_out_24h += int(tokens_out)
```

**Patch** `app/billing/cost_estimator.py`:
```python
def estimate_daily_cost() -> Dict:
    snap = tracker.snapshot()
    cfg = load_all()
    total_usd = 0.0
    breakdown = []
    for tool_name, usage in snap.items():
        match = _model_to_provider(tool_name)
        if not match:
            continue
        provider, alias = match
        model = next((m for m in cfg[provider].get("models", []) if m.get("alias") == alias), None)
        if not model:
            continue
        # 016 — gerçek token sayısı varsa kullan, yoksa eski avg fallback
        tok_in = usage.get("tokens_in_24h", 0)
        tok_out = usage.get("tokens_out_24h", 0)
        if tok_in == 0 and tok_out == 0:
            avg_per_call = 1500
            tok_in = int(usage["count_24h"] * avg_per_call * 0.3)
            tok_out = int(usage["count_24h"] * avg_per_call * 0.7)
        cost_in = (tok_in / 1_000_000) * float(model.get("pricing_per_mtok_input", 0))
        cost_out = (tok_out / 1_000_000) * float(model.get("pricing_per_mtok_output", 0))
        cost = round(cost_in + cost_out, 4)
        total_usd += cost
        breakdown.append({"tool": tool_name, "provider": provider,
                          "tokens_in": tok_in, "tokens_out": tok_out,
                          "estimated_usd": cost,
                          "exact": tok_in > 0 or tok_out > 0})
    return {"today_usd": round(total_usd, 2),
            "projected_monthly_usd": round(total_usd * 30, 2),
            "breakdown": sorted(breakdown, key=lambda x: -x["estimated_usd"])[:10],
            "estimated_at": time.time()}
```

**Patch** `app/cascade/orchestrator.py` — başarılı `provider.call` sonrası:
```python
resp = await provider.call(prompt, model=model)
# 016 — token'ları tracker'a forward (orchestrator-level çağrılarda)
# Pipeline'ların kendi tool'undan tracker.bump() çağırılıyor; çift sayım önlemek için
# orchestrator burada bump etmiyor — tool_name yok.
```

(Orchestrator tool_name bilmediği için bump etmesin; bunun yerine pipeline tool wrapper'ları çağırırken token forward etsin.)

**Patch** `app/mcp/tools/pipelines.py` — `_format_meta` sonrası:
```python
# 016 — pipeline result token sayılarını tracker'a forward et
total_in = sum(int(s.meta.get("tokens_in", 0)) for s in result.steps if s.meta)
total_out = sum(int(s.meta.get("tokens_out", 0)) for s in result.steps if s.meta)
# tracker.bump zaten her tool'da çağrılıyor — burada sadece token ekleyemeyiz
# (UsageTracker.bump signature değişti). Tool wrapper'ları update et:
```

Doğrudan `qual_code` tool fonksiyonunda:
```python
@mcp_server.tool()
async def qual_code(prompt: str) -> str:
    res = await QualCodePipeline().run(prompt)
    total_in = sum(int(s.meta.get("tokens_in", 0)) for s in res.steps if s.meta)
    total_out = sum(int(s.meta.get("tokens_out", 0)) for s in res.steps if s.meta)
    await tracker.bump("qual_code", tokens_in=total_in, tokens_out=total_out)
    return _format_meta(res)
```

(Aynı patch 13 pipeline tool'u için tek tek; mekanik refactor — worker zamansa basic_providers tool'larındaki `_call(provider, prompt, ...)` helper'a token forward ekle: `_call` ProviderResponse döndüğüne göre `resp.tokens_in/out`'u bump'a forward et.)

**`pipelines/execution.py::timed_step`** — ProviderResponse'tan token meta'ya yazsın:
```python
async def timed_step(name, coro, model_hint=""):
    # ... mevcut
    if result is not None:
        meta = {}
        ti = getattr(result, "tokens_in", None)
        to = getattr(result, "tokens_out", None)
        if ti is not None: meta["tokens_in"] = ti
        if to is not None: meta["tokens_out"] = to
        step.meta.update(meta)
    return step, result
```

**Test** `tests/test_token_tracking.py` (~110 satır, 4 test):

1. `test_tracker_bump_accepts_tokens`: `tracker.bump("ask_test", tokens_in=100, tokens_out=200)` → snapshot içinde `tokens_in_24h==100`.
2. `test_tracker_bump_accumulates`: 3x bump → tokens_in_24h toplam.
3. `test_cost_estimator_uses_real_tokens_when_available`: mock tracker tokens set → `breakdown[0]["exact"]==True`, `tokens_in` correct.
4. `test_cost_estimator_falls_back_to_avg`: tokens 0 + count_24h>0 → fallback avg 1500 calc.

### E. MCP Tools

**Yeni dosya** `app/mcp/tools/innovation_tools.py` (~80 satır, 3 tool):

```python
"""Innovation MCP tools (016) — symbol_search + rag_hybrid + judge_persona_predict."""
from __future__ import annotations
import json
from typing import List, Optional
from app.mcp.middleware import with_hooks
from app.mcp.server import mcp_server
from app.mcp.tracking import tracker

REGISTERED_TOOLS: List[str] = []


@mcp_server.tool()
@with_hooks("symbol_search")
async def symbol_search(q: str, kind: Optional[str] = None, limit: int = 20) -> str:
    """Symbol DB substring search — name LIKE %q%, opsiyonel kind=function|class|import."""
    await tracker.bump("symbol_search")
    from app.symbols.store import search
    return json.dumps({"query": q, "results": search(q, limit=limit, kind=kind)},
                      ensure_ascii=False, indent=2)


@mcp_server.tool()
@with_hooks("rag_hybrid")
async def rag_hybrid(question: str, project_filter: Optional[str] = None,
                     top_k: int = 5, alpha_semantic: float = 0.6) -> str:
    """RAG hybrid retrieval — BM25 + cosine fusion. alpha_semantic 0=BM25 only, 1=cosine only."""
    await tracker.bump("rag_hybrid")
    from app.rag.hybrid import query_hybrid
    res = await query_hybrid(question, project_filter=project_filter,
                             top_k=top_k, alpha_semantic=alpha_semantic)
    return json.dumps(res, ensure_ascii=False, indent=2)


@mcp_server.tool()
@with_hooks("judge_persona_predict")
async def judge_persona_predict(ast_score: float, llm_score: float,
                                persona_drift: float) -> str:
    """ML model ile bu skorların accept olasılığını tahmin et."""
    await tracker.bump("judge_persona_predict")
    from app.judge.ml_persona import predict_accept
    return json.dumps(predict_accept(ast_score, llm_score, persona_drift),
                      ensure_ascii=False, indent=2)


REGISTERED_TOOLS.extend(["symbol_search", "rag_hybrid", "judge_persona_predict"])
```

**Patch** `app/mcp/server.py::register_all_tools` — `from app.mcp.tools import innovation_tools` import + count.
**Patch** `tests/test_tools_count.py`: 99 → 102 + 3 must_have.

## Kısıtlar

- **Mevcut 247 test korunmalı.**
- **Symbol DB testlerde `tmp_path data_dir` ile izole** (autouse fixture mevcut zaten).
- **RAG hybrid testlerde Chroma + embedding mock** — gerçek Ollama yok.
- **ML persona logistic regression numpy gerektirmiyor** — saf Python (math.exp). Sklearn opsiyonel, default kullanılmıyor.
- **Token forward `_call` helper'a uygulanırken backward compat** — eski tool çağrıları (kwargs olmadan) hâlâ çalışmalı (`tokens_in=0, tokens_out=0` default).
- **pytest 268+ veya 266+ skip** zorunlu.
- **Freeze AKTIF.**

## Adımlar (Worker Claude için)

### 1. Önkoşul (5 dk)
```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                       # 247 + 2 skipped
```

### 2. Modul A — Symbol Graph (60 dk)
1. `app/symbols/__init__.py` (re-export)
2. `app/symbols/parser.py` (Python AST visitor)
3. `app/symbols/store.py` (SQLite + neighbors BFS)
4. `app/symbols/index.py` (orchestrator)
5. `app/api/symbol_graph.py` Write tam override (5 endpoint)
6. `tests/test_symbols_parser.py` (5 test)
7. `pytest tests/test_symbols_parser.py -v` → 5 PASS

### 3. Modul B — RAG Hybrid (45 dk)
1. `app/rag/hybrid.py` (BM25 + cosine fusion)
2. `tests/test_rag_hybrid.py` (5 test, mock Chroma + embed)
3. `pytest tests/test_rag_hybrid.py -v` → 5 PASS

### 4. Modul C — ML Persona Training (45 dk)
1. `app/judge/ml_persona.py` (logistic regression saf Python)
2. `tests/test_judge_ml_persona.py` (4 test, fake judge_log entries)
3. `pytest tests/test_judge_ml_persona.py -v` → 4 PASS

### 5. Modul D — Token Tracking (40 dk)
1. `app/mcp/tracking.py` patch — `bump(tokens_in, tokens_out)` parametreleri + `tokens_in_24h`/`tokens_out_24h`
2. `app/pipelines/execution.py::timed_step` patch — ProviderResponse tokens → step.meta
3. `app/mcp/tools/pipelines.py` patch — 13 tool'da `tracker.bump("...", tokens_in=total, tokens_out=total)` (helper fn refactor)
4. `app/billing/cost_estimator.py` patch — gerçek token + fallback
5. `tests/test_token_tracking.py` (4 test)
6. `pytest tests/test_token_tracking.py -v` → 4 PASS
7. Regresyon: `pytest tests/test_cost_estimator.py -v` → 4 PASS (eski testler hâlâ yeşil)

### 6. Modul E — MCP Tools (15 dk)
1. `app/mcp/tools/innovation_tools.py` (3 tool)
2. `app/mcp/server.py` Read → tam Write override (innovation_tools import + count)
3. `tests/test_tools_count.py` patch (99 → 102, 3 yeni isim)
4. `pytest tests/test_tools_count.py -v` → 2 PASS

### 7. Tam Test Suite (5 dk)
```bash
.venv/bin/pytest -q
# 268+ passed (+2 skipped)
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 102
```

### 8. Live MCP Smoke (15 dk)
```bash
mkdir -p /tmp/abs-016-smoke/{data,evidence}
ABS_DATA_DIR=/tmp/abs-016-smoke/data .venv/bin/uvicorn app.main:app --port 8765 &

# 4 kanıt /tmp/abs-016-smoke/evidence/:
# 01: POST /api/symbol-graph/index {path:"app/"} → indexed:N (kendi codebase'ini index)
# 02: symbol_search MCP "tracker" → results listesi
# 03: rag_hybrid MCP "what is workflow" → top_k results (Chroma boşsa empty list)
# 04: judge_persona_predict (8.0, 7.5, 0.2) → p_accept değeri (model trained değilse error)
```

### 9. Tamamlama
1. `_agent-tasks/completed/016-symbol-rag-ml-tokens.md` taşı
2. `016-symbol-rag-ml-tokens-summary.md` yaz:
   - 4 modül + dosya listesi
   - Test sonuçları (247 → 268+)
   - 4 smoke kanıtı
   - Notlar Planlayıcıya
   - **Bu son innovation task — production-ready feature parity tamam**

## Doğrulama (Worker fail-fast)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                                # 268+ passed
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"  # 102
.venv/bin/python -c "from app.symbols.parser import parse_python_file; from pathlib import Path; print(len(parse_python_file(Path('app/main.py'))))"
# >0 (main.py'da fonksiyon var)
.venv/bin/python -c "from app.judge.ml_persona import model_status; print(model_status())"
# {'trained': False}
```

## Notlar Planlayıcıya (Worker doldursun)

- **Symbol indexing TypeScript/JS YOK** — sadece Python AST. JS/TS ayrı parser (tree-sitter veya esprima) ile 017+'ya bırakıldı.
- **Symbol DB cron re-index** — file change detection yok; manuel tetikle (`POST /api/symbol-graph/index`). Watchdog 017'de schedule edebilir.
- **RAG hybrid alpha_semantic** default 0.6 — empirik; müşteri tarafında tunable env (`ABS_RAG_ALPHA_SEMANTIC`) opsiyonel 017+'da.
- **ML persona threshold 0.5** sabit — production'da ROC AUC ile optimal threshold bulunabilir 017+'da.
- **Token tracking pipeline tool'larında** — basic_providers tool'ları ProviderResponse zaten dönüyor; `_call` helper'da forward edilmeli. Worker bu refactor'u kapsamlı yaptı mı, atladı mı summary'de belirtsin.
- **Cost estimator gerçek token** — tracker boyut artışı önemsiz (sadece 2 int alan).

## Bu Task Sonrası

- **016 = son innovation task.** Production feature parity tamamlanmış olur.
- **017+** = panel UI polish, customer onboarding email serisi, marketplace listing, multi-language docs, performance benchmarks
- Ürünleştirme aşamasına geçilebilir (decision_20260423_product_discussion.md)

## Kapsam Dışı (017+'a)

- TypeScript/JS symbol parsing (tree-sitter)
- Symbol DB cron re-index + file watch
- RAG alpha tuning UI (panel slider)
- ML persona ROC threshold optimization
- Token tracking provider-level (basic_providers _call helper full refactor)
- Multi-tenant symbol DB
- Symbol graph görselleştirme (panel widget)
