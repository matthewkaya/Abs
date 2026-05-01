# Task 021 — Performance Benchmarks (Cascade + Vault + Symbol + Watchdog)

**Status:** READY (Worker)
**Tahmini süre:** 3-4 saat
**Bağımlı task'lar:** 005 (cascade), 013 (vault), 014 (watchdog), 016 (symbol graph), tüm önceki
**Hedef sonuç:** Production VPS'te beklenebilecek performansı ölçen 4 benchmark + grafik raporu. Müşteriye "X req/s, Y ms p99" iddialarını veri ile destekle.

---

## 0. Bağlam

ABS production'a yakın ama performans rakamları yok:
- Cascade router 6 provider arasında seçim yapıyor — latency ne?
- Vault decrypt boot'ta — kaç ms ek?
- Symbol graph 10K LOC repo index — kaç dakika?
- Watchdog VPS'te ne kadar RAM/CPU yer?

Marketing material için "100 req/s, p99 < 500ms" gibi iddialar lazım. 021: locust + pytest-benchmark + standalone profiler script'leri ile ölç.

---

## 1. Amaç (DoD)

- [ ] `benchmarks/cascade_load.py` — locust load test (100 req/s, 5dk)
- [ ] `benchmarks/vault_overhead.py` — pytest-benchmark sops decrypt timing
- [ ] `benchmarks/symbol_indexing.py` — 10K LOC sample repo index time
- [ ] `benchmarks/watchdog_resources.py` — psutil RSS + CPU sample
- [ ] `docs/performance.md` — 4 benchmark sonucu + grafik (matplotlib)
- [ ] CI workflow `.github/workflows/benchmarks.yml` (haftalık çalışsın, regression alert)
- [ ] 8 yeni test (her benchmark için validation + meta)
- [ ] 4 smoke evidence (her benchmark sonucu JSON)
- [ ] MCP tool `perf_summary` — son benchmark sonuçlarını döner
- [ ] Tool count 104 → 105
- [ ] Test 316 → 324

---

## 2. Modüller

### Modul A — Cascade Load Test
`benchmarks/cascade_load.py` (locust):
```python
from locust import HttpUser, task, between

class CascadeUser(HttpUser):
    wait_time = between(0.1, 0.5)

    @task
    def call_ask_gptoss(self):
        self.client.post(
            "/v1/cascade/ask",
            json={"prompt": "test", "model": "gptoss"},
            timeout=30,
        )
```

Çalıştırma:
```bash
locust -f benchmarks/cascade_load.py \
  --host http://localhost:8000 \
  --users 100 --spawn-rate 10 \
  --run-time 5m \
  --html /tmp/abs-021-smoke/evidence/01_cascade_load.html \
  --csv /tmp/abs-021-smoke/evidence/01_cascade_load \
  --headless
```

Hedef: p99 < 1000ms (free tier providers değişken, gerçekçi).

### Modul B — Vault Decrypt Overhead
`benchmarks/vault_overhead.py` (pytest-benchmark):
```python
def test_vault_decrypt_overhead(benchmark):
    result = benchmark(decrypt_vault_file, "/path/to/secrets.enc.json")
    assert result is not None
```

Hedef: < 50ms (sops + age 4096-bit RSA).

### Modul C — Symbol Indexing
`benchmarks/symbol_indexing.py`:
- Mock repo: 10K LOC Python (auto-generate veya gerçek small repo clone)
- `app.symbols.indexer.index_repo(path)` time
- Hedef: < 60s (Python AST + SQLite write).

### Modul D — Watchdog Resources
`benchmarks/watchdog_resources.py`:
- Watchdog process başlat, 10dk çalıştır
- psutil ile her 10s sample (RSS, CPU%, threads, fds)
- Output: JSON time-series

Hedef: RSS < 200MB, CPU avg < 5%.

### Modul E — Reporting
`docs/performance.md` template:
```markdown
# Performance Benchmarks

Last run: 2026-04-27 — VPS hardware: Hetzner CPX21 (2 vCPU, 4GB RAM)

## Cascade Latency
- p50: 320ms, p95: 850ms, p99: 1200ms (Groq+CF mix)
- Throughput: 95 req/s sustained

## Vault Decrypt
- Mean: 38ms, max: 65ms
- Overhead: negligible (boot only)

## Symbol Indexing
- 10K LOC: 42s (AST parse + SQLite write)
- Memory peak: 180MB

## Watchdog
- RSS: 145MB stable
- CPU: 2.3% avg, 8% peak
```

Matplotlib grafikleri PNG olarak `docs/perf-charts/` altına.

### Modul F — MCP Tool perf_summary
`app/mcp/tools/perf_tools.py`:
```python
async def perf_summary() -> dict:
    """Son benchmark çalıştırma sonuçlarını oku (JSON files)."""
    return {
        "cascade": {...},
        "vault": {...},
        "symbol": {...},
        "watchdog": {...},
        "last_run": "2026-04-27",
    }
```

### Modul G — CI Workflow
`.github/workflows/benchmarks.yml`:
```yaml
name: weekly-benchmarks
on:
  schedule:
    - cron: '0 3 * * 1'  # Pazartesi 03:00 UTC
  workflow_dispatch: {}
jobs:
  bench:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
      - run: pip install -r benchmarks/requirements.txt
      - run: bash benchmarks/run_all.sh
      - uses: actions/upload-artifact@v4
        with: { name: benchmark-results, path: benchmarks/results/ }
```

---

## 3. Test Stratejisi (8 test)

| Dosya | Test |
|---|:-:|
| `tests/test_cascade_benchmark_meta.py` | 2 (locust file syntax, scenario validate) |
| `tests/test_vault_benchmark.py` | 2 (decrypt run, time threshold) |
| `tests/test_symbol_benchmark.py` | 2 (indexer run, time threshold) |
| `tests/test_watchdog_benchmark.py` | 1 (psutil sampler validate) |
| `tests/test_perf_summary_mcp.py` | 1 (tool response shape) |
| `tests/test_tools_count.py` | (104 → 105 update) |

Toplam: 316 → 324.

---

## 4. Smoke Evidence

1. `01_cascade_load.csv` — locust raw stats
2. `02_vault_decrypt_timing.json` — pytest-benchmark JSON
3. `03_symbol_indexing.json` — index time + memory
4. `04_watchdog_resources.json` — 10dk time-series

---

## 5. Adım Adım

```
1. baseline pytest 316 + tool 104
2. pip install locust pytest-benchmark psutil matplotlib (.venv)
3. Modul A: cascade locust + 5dk run + evidence
4. Modul B: vault pytest-benchmark + threshold test
5. Modul C: symbol indexing 10K LOC sample
6. Modul D: watchdog 10dk sample
7. Modul E: docs/performance.md + grafikler
8. Modul F: perf_summary MCP tool + count 104→105
9. Modul G: CI workflow
10. summary + completed/
```

## 6. DoD Checklist

```
[ ] 4 benchmark script çalıştırıldı
[ ] docs/performance.md yazıldı + grafikler
[ ] CI workflow eklendi
[ ] 8 test yeşil + tool count 105
[ ] 4 smoke evidence
[ ] backend regression yeşil
[ ] summary + completed/
```

## 7. Worker Notları

1. **Cascade load test backend live çalışırken** — `uvicorn app.main:app &` background, locust ona vurur. Test sonrası kill.
2. **Free tier provider quota** — 100 req/s 5dk = 30K request, Groq/CF quota limit yer. Test mode'da `provider_mock=True` kullan ya da locust user 10'a düşür.
3. **psutil 10dk sample** — uzun süreli, worker bunu blocking çalıştırmamalı. Background subprocess + tail.
4. **Matplotlib** dependency büyük (~50MB). `benchmarks/requirements.txt` ayrı tut, ana requirements'a karıştırma.
5. **`docs/performance.md`** içerik delegation OK ama veri (number'lar) gerçek run'dan gelmeli — placeholder yazma.
6. **CI workflow ilk koşunca** sonuç regression baseline olarak commit edilmeli (manual ilk seferinde).
7. **VPS test** — 021 lokalde çalışsın, gerçek VPS benchmarks 022+'ya kalsın.
