# Task 014 — Update Channel + Provider Configs + Health Monitor + Breaker Persist + Watchdog Skeleton (SUMMARY)

**Tamamlandı:** 2026-04-25
**Süre:** ~1.5 saat (planlanan 4-5h altında — şablonlar tam)
**Sonuç:** 7 modül + Lifespan integration + SSE async builder + watchdog skeleton.

## Özet

| Hedef | Önce | Sonra | Δ |
|-------|------|-------|---|
| pytest yeşil | 194 + 2 skip | **223 passed + 2 skipped** | +29 (+2 skip korundu) |
| MCP tool sayısı | 93 | **96** (`update_check`, `health_status`, `breaker_status`) | +3 |
| SSE event count | 6 | **7** (+`update-available`) | +1 |
| Provider config files | 0 | **6 YAML** (anthropic/groq/gemini/cerebras/cohere/cloudflare) | +6 |
| Health monitor | random placeholder | gerçek 60s ping loop | yeni |
| Breaker persist | memory-only | `data_dir/breaker_state.json` (atomic) | yeni |
| Watchdog skeleton | yok | `infra/watchdog/{scanner,alerter,cron,README}` | yeni |

## Modul A — Update Channel (5 endpoint + manifest)

**Yeni dosyalar:**
- `app/update/__init__.py` — re-export
- `app/update/manifest.py` (~110 satır) — `fetch_manifest()` async (httpx + 6h cache), `compare_versions()` semver-lite (malformed → 0), `update_state()` → `current|available|critical|unknown`
- `app/update/applier.py` (~55 satır) — `trigger_pull()` data_dir/update_pending.json flag yazar (container içinde docker pull ÇALIŞTIRMAZ), `pending_status()`, `clear_pending()`
- `app/api/update.py` (~55 satır) — 5 endpoint: GET /check (public), GET /changelog (admin), POST /apply (admin), GET /pending (admin), DELETE /pending (admin)

**Patch'ler:**
- `app/config.py` — `update_manifest_url`, `health_interval_seconds`
- `app/main.py` — eski `/v1/update/channel` placeholder SİLİNDİ + `update_router` register

**Yeni test:** `tests/test_update_channel.py` (6 test) → **6/6 PASS** (5 zorunlu + 1 ek pending endpoint)

## Modul B — Provider Configs YAML

**Yeni dosyalar (6 YAML):**
- `infra/provider-configs/anthropic.yaml` — claude-haiku/sonnet/opus + pricing per MTok
- `infra/provider-configs/groq.yaml` — llama-3.3-70b, gpt-oss-120b/20b, kimi-k2, qwen-3-32b, llama-4-scout (free tier)
- `infra/provider-configs/gemini.yaml` — gemini-flash/pro/flash-lite (1-2M context)
- `infra/provider-configs/cerebras.yaml` — llama-3.3-70b, qwen-3-32b, llama-3.1-8b
- `infra/provider-configs/cohere.yaml` — command-r-plus/r, embed-multilingual-v3
- `infra/provider-configs/cloudflare.yaml` — kimi-k2, deepseek-r1-distill, llama-3.3-70b, gpt-oss-120b, qwen-coder

**Yeni dosya:** `app/providers/configs.py` (~70 satır) — `load_all(directory?)`, `get(provider)`, `get_model_alias(provider, alias)`, `deprecated_models(provider)`, `all_providers()`. Path resolver: dev'de `parents[4]/infra/provider-configs`, prod'da `ABS_PROVIDER_CONFIGS_DIR` env override.

**Patch:** `app/main.py::lifespan` — `load_all()` boot'ta çağrılır, sayı log'a yazılır.

**Yeni test:** `tests/test_provider_configs.py` (5 test) → **5/5 PASS** (4 zorunlu + 1 sanity check repo'daki 6 yaml yüklensin)

## Modul C — Health Monitor 60s Loop

**Yeni dosyalar:**
- `app/health/__init__.py` — `HealthMonitor` + `ProviderHealth` re-export. **`monitor` instance INDIRECT** — submodule shadow problemini önlemek için doğrudan `from app.health.monitor import monitor` kullanılır.
- `app/health/monitor.py` (~115 satır) — `HealthMonitor` class, `_ping_one(provider)` cheap ping (max_tokens=5, timeout=8s), `_run()` async loop, `start()/stop()`, snapshot `[{name, state, latency_ms, last_check_at, last_error}]`

State değerleri: `ok` (latency<3s), `warn` (latency≥3s veya 1. fail), `down` (≥2 ardışık fail), `unknown` (no credentials). `_KEY_MAP` 7 provider key→settings attr.

**Patch:** `app/api/stream.py::_build_orchestrator` — random placeholder kalktı, `monitor.snapshot()` kullanır. Boş ise fallback `unknown` listesi. `_build_judge_placeholder()` 015'te real feed'e bağlanacak.
**Patch:** `app/main.py::lifespan` — `ABS_TEST_MODE=1` haricinde `monitor.start()` + `try/finally monitor.stop()`.

**Yeni test:** `tests/test_health_monitor.py` (6 test) → **6/6 PASS** (4 zorunlu + 2 ek snapshot+stream integration)

## Modul D — Circuit Breaker Persist

**Yeni dosya:** `app/cascade/persist.py` (~50 satır)
- `save(states)` — atomic temp+replace, `{provider: {state, fail_count, opened_at_real_time}}`
- `load()` — file yoksa `{}`, parse hata sessiz `{}`
- `cleanup()` — sil

**Patch:** `app/cascade/breaker.py`
- `record_failure()` ve `record_success()` sonunda `self._persist()` çağrısı
- Yeni `restore_state()` method — `time.time() - opened_at_real_time >= reset_timeout_seconds` ise atla; `monotonic` re-baseline ile state korunur
- Yeni `_persist()` — yalnız `open` ve `half_open` state'ler diske yazılır; closed olunca `save({})`

**Yeni test:** `tests/test_breaker_persist.py` (5 test) → **5/5 PASS** (4 zorunlu + 1 ek closed reset)

**Regression:** `tests/test_cascade.py` 7/7 hâlâ yeşil — persist eklenmesi mevcut breaker davranışını bozmadı.

## Modul E — 3 MCP Tools + 96 Guard

**Yeni dosya:** `app/mcp/tools/update_tools.py` (~55 satır, 3 tool)
- `update_check` — `fetch_manifest + update_state` JSON
- `health_status` — `monitor.snapshot()` JSON
- `breaker_status` — `default_breaker.snapshot()` JSON

**Patch:** `app/mcp/server.py` (tam Write override) — `update_tools` import + count
**Patch:** `tests/test_tools_count.py` — 93 → **96 guard**, must_have'a 3 tool

**Test:** 2/2 PASS. `_REGISTERED_COUNT == 96`.

## Modul F — Panel Update Banner UI

**Patch'ler:**
- `app/static/panel/index.html` — alert-bar üstüne `<div id="update-banner">` (icon + version + summary + Güncelle button + dismiss). Demo banner zaten 012'de eklenmişti, yan yana.
- `app/static/panel/assets/panel.css` — `.update-banner` (brand gradient), `.update-critical` (#ef4444), `.update-banner-action` (white CTA)
- `app/static/panel/assets/panel.js` — `addEventListener("update-available", onUpdateAvailable)`, `applyUpdate()` (POST /v1/update/apply + alert), `dismissUpdateBanner()`, window expose
- `app/api/stream.py` — `_EVENT_ORDER` → `update-available` 7. event, `_build_update_available()` async builder + `_BUILDERS["update-available"]`
- `_event_generator()` — `inspect.iscoroutinefunction()` ile async builder destek (sync builder'lar etkilenmedi); builder exception → `{error: "builder fail"}`

**Yeni test:** `tests/test_panel_update_banner.py` (4 test) → **4/4 PASS**

**Regression:** test_panel_banner.py 3/3 + test_panel.py 6/6 = 9 yeşil.

## Modul G — Watchdog Skeleton

**Yeni dosyalar (infra/watchdog/, backend container'da çalışmaz):**
- `__init__.py` — paket
- `scanner.py` (~50 satır) — `_FEEDS` dict (groq/anthropic/gemini/cohere/cerebras/cloudflare), `scan_changelog(provider)` stub, `scan_all()` list
- `alerter.py` (~25 satır) — `send_discord_alert(msg)` async, `WATCHDOG_DISCORD_WEBHOOK` env yoksa False (exception yok)
- `cron.py` (~25 satır) — `main()` async, `scan_all() + send_discord_alert()` entry point
- `README.md` (~40 satır) — Hetzner VPS deploy talimatı, crontab, env config

**Yeni test:** `tests/test_watchdog_skeleton.py` (3 test) → **3/3 PASS** (2 zorunlu + 1 README doc check). `sys.path.insert(0, repo/infra)` ile import erişimi.

## Test Sonuçları

```
.venv/bin/pytest -q
223 passed, 2 skipped in 6.11s
```

**Önce:** 194 + 2 skip. **Sonra:** 223 + 2 skip. **Hedef:** 215+. **+29 yeni test:**
- test_update_channel.py: 6
- test_provider_configs.py: 5
- test_health_monitor.py: 6
- test_breaker_persist.py: 5
- test_tools_count.py: 0 (mevcut 2 test 96 guard'a güncellendi)
- test_panel_update_banner.py: 4
- test_watchdog_skeleton.py: 3

**+2 SKIP** 013'ten korundu (sops binary olmadan vault_runner real-roundtrip).

**Mevcut 194 test korundu:**
```
test_setup_wizard.py        7/7 PASS
test_panel.py               6/6 PASS  (banner ekleme bozmadı)
test_panel_banner.py        3/3 PASS
test_stream_real_data.py    2/2 PASS  (orchestrator monitor entegrasyonu, license-status hâlâ)
test_cascade.py             7/7 PASS  (persist eklendi)
test_license_api.py         3/3 PASS
... (toplam 194 + 29 = 223)
```

## Live MCP Smoke (Kanıtlar `/tmp/abs-014-smoke/evidence/`)

uvicorn `--port 8769` (env override: tmp dirs, `ABS_UPDATE_MANIFEST_URL=https://abs.local/manifest.json`).

### 1. `update_check` (MCP) — manifest URL erişilmez → `state:unknown` graceful
```json
{
  "state": "unknown",
  "error": "[Errno 8] nodename nor servname provided, or not known",
  "current": "0.1.0"
}
```
Doğru graceful path — manifest yokken hata sızmadan state="unknown" döner.

### 2. `health_status` (MCP) — 6 provider unknown (no credentials)
```json
{
  "providers": [
    {"name": "Cerebras", "state": "unknown", "latency_ms": 0, "last_error": "no credentials configured"},
    {"name": "Cloudflare", "state": "unknown", ...},
    {"name": "Gemini", "state": "unknown", ...},
    {"name": "Groq", "state": "unknown", ...},
    {"name": "Mlx", "state": "unknown", ...},
    {"name": "Ollama", "state": "unknown", ...}
  ]
}
```
Health monitor live mode'da başladı, 6 provider ping atmaya başladı (ABS_TEST_MODE skip değil). Credentials yokken state="unknown" — beklenen.

### 3. `breaker_status` (MCP) — boş (henüz hiçbir provider çağrılmadı)
```json
{"states": {}}
```

### 4. `GET /v1/update/check` (REST) — MCP ile aynı payload
```json
{"state":"unknown","error":"[Errno 8] nodename nor servname provided, or not known","current":"0.1.0"}
```

MCP tools/list = **96** init handshake OK.

## Notlar Planlayıcıya

1. **Update apply container içinde docker pull ÇALIŞTIRMAZ** — sadece `data_dir/update_pending.json` flag yazar. Host-side cron veya systemd unit pickup eder. **Operations doc'a not** (`docs/operations.md`) 015+'a düşüldü. Müşteri host'ta manuel `docker compose pull && up -d` çalıştırır.

2. **Manifest URL placeholder** `https://abs.automatiabcn.com/releases/manifest.json` — domain henüz live değil. Müşteri `ABS_UPDATE_MANIFEST_URL` env ile override edebilir. `state:"unknown"` graceful path live'da test edildi.

3. **Watchdog Hetzner deploy 015 kapsamında** — bu task sadece iskelet. `infra/watchdog/README.md` deploy talimatı içeriyor. Gerçek scrape parser'lar provider başına 015'te yazılacak (BeautifulSoup/lxml).

4. **`/mcp` whitelist 012'de eklenmişti** — health/breaker MCP tool'ları setup öncesi de erişilebilir. Production gate `mcp_require_license=True` ise 011 license_gate devreye girer.

5. **Health monitor `ABS_HEALTH_INTERVAL` env yok şu an** — `health_interval_seconds: int = 60` config'e eklenmiş ama runtime override için env yapısı eksik. 015'te `Settings` env_prefix zaten `ABS_` olduğu için `ABS_HEALTH_INTERVAL_SECONDS=30` çalışacak — sadece dokümante edilmesi lazım.

6. **Provider configs YAML schema validation** — şu an `provider` key'i şart, gerisi opsiyonel. `jsonschema` ile sıkı validate 015+'a.

7. **Manifest signature verification** (RS256 imzalı manifest) **YOK** — supply-chain attack açık. Production'da kritik. 015'te ekle (lisans imza altyapısı zaten var, manifest için yeniden kullanılabilir).

8. **Breaker persist debounce yok** — her record_failure persist çağırır. Yüksek RPS senaryosunda optimize. Şu an 5 fail → open + 1 file write, 1 success → closed + 1 write. CPU/IO etki minimal.

9. **`app.health` __init__ shadow sorunu** — submodule `monitor` aynı isimle re-export edilince `import app.health.monitor as mod` testlerde HealthMonitor instance dönüyordu. Çözüm: `__init__.py`'da `monitor` instance YOK, sadece class re-export. Tests hep `from app.health.monitor import monitor` (submodule path) kullanır.

10. **SSE async builder support** — 014'te `update-available` event async fetch_manifest çağırıyor. `_event_generator` `inspect.iscoroutinefunction()` ile sync/async ayırıyor; mevcut 5 sync builder etkilenmedi.

## Feature Parity

014 SERVER paritesinden ileriye geçer:
- Update channel: SERVER yok (orchestrator localhost'ta version yönetimi yok)
- Provider configs YAML: SERVER'da inline dict; ABS'de config-driven
- Health monitor: SERVER'da yok (orchestrator panel istiyor → 015 panel real data ile bağlanacak)
- Breaker persist: SERVER memory-only
- Watchdog: tamamen yeni

Atlanan parity yok.

## Doğrulama (Fail-Fast)

```bash
$ .venv/bin/pytest -q
223 passed, 2 skipped in 6.11s

$ .venv/bin/pytest tests/test_tools_count.py -v
2 passed

$ .venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
96

$ .venv/bin/python -c "from app.providers.configs import load_all; print(len(load_all()))"
6

$ .venv/bin/python -c "from app.health.monitor import monitor; print(monitor.snapshot())"
[]
```

Hepsi yeşil.

## Kapsam Dışı (015+'a)

- Watchdog production deploy (Hetzner cron, real scrape parsers)
- Manifest signature verification (RS256)
- Update breaking-change migration script
- Panel `cache_stats`, `today_usd`, `learnings_count`, `symbol_graph` real data (placeholder kalan) — **015'in çekirdeği**
- Provider configs JSON schema validation
- Health monitor interval tuning + alert webhook
- Update auto-apply (cron-driven) — şu an sadece manuel onay
- Multi-channel release tracks (stable/beta/canary)
- `docs/operations.md` host-side update workflow guide
