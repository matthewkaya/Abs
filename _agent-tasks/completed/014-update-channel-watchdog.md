# Task 014 — Update Channel + Provider Configs + Health Monitor + Breaker Persist + Watchdog Skeleton

**Tahmini süre:** 4-5 saat (7 modül + watchdog iskelet + provider config YAML + health loop)
**Önkoşul:** 013 tamam (93 MCP tool, 194 passed + 2 skipped, encrypted vault çalışıyor)

## Bağlam

Müşteri akışı bugüne kadar: ödeme (011) → kurulum (012) → encrypted vault (013). Eksik: **release lifecycle** ve **runtime observability**.

011-013 boyunca **release/update kanalı** ve **provider health observability** placeholder kaldı:
- `/v1/update/channel` GET stub: `{"channel":"stable","current":"0.1.0"}` — sadece versiyon string, manifest karşılaştırması yok
- `_build_orchestrator()` SSE event'i hâlâ random — gerçek provider ping yok
- `app/cascade/breaker.py` memory-only — restart sonrası 5 hata/60s state'i kaybolur
- `infra/provider-configs/*.yaml` yok — model alias map config-driven değil
- ABS Central Watchdog (Hetzner cron, design-decisions md.22) iskeleti yok

014 bu 5 boşluğu kapatır + watchdog iskeleti ekler:

1. **Update Channel** — `/v1/update/{check,changelog,apply}` endpoint'leri, remote `manifest.json` fetch + karşılaştır + admin onayıyla docker-compose pull tetikle
2. **Provider Configs** — `infra/provider-configs/{groq,gemini,cohere,...}.yaml` model alias map + pricing + deprecation flag, boot'ta registry'ye apply
3. **Health Monitor** — 60s cron loop, tüm provider'lara cheap ping (1 token request), in-memory status dict, SSE `_build_orchestrator` real data
4. **Circuit Breaker Persist** — `data_dir/breaker_state.json` atomic save/restore, restart sonrası 5 dakikalık open state korunur
5. **Watchdog Skeleton** — `infra/watchdog/{scanner,alerter}.py` iskelet (Python cron service, Hetzner deploy 015+'a)
6. **Panel Update Notification** — SSE `update-available` event + banner UI (yeşil/mavi/kırmızı state)
7. **MCP Tools** — `update_check`, `health_status`, `breaker_status`

**Tool sayısı hedefi:** 93 → **96 tool** (+3).
**Test sayısı hedefi:** 194 → **~215+ test** (+21: 5 update channel, 4 provider configs, 4 health monitor, 4 breaker persist, 2 watchdog smoke, 2 panel banner).

## Giriş (Mevcut Durum — Worker doğrulasın)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                       # 194 passed + 2 skipped
.venv/bin/python -c "from app.cascade.breaker import CircuitBreaker; b = CircuitBreaker(); print('breaker:', type(b).__name__)"
ls app/cascade/                                          # breaker.py, cache.py, orchestrator.py
.venv/bin/python -c "from app.main import app; print('version:', app.version)"
# version: 0.1.0
curl -s http://localhost:8765/v1/update/channel 2>&1 | head -3 || true   # placeholder mevcut (boot etmezsen N/A)
```

**Mevcut altyapı:**
- `app/cascade/breaker.py` — `CircuitBreaker` class, fail_threshold=5, reset 60s, in-memory `_states`
- `app/cascade/orchestrator.py` — provider cascade chain
- `app/api/stream.py::_build_orchestrator` — random provider state placeholder (014'te real)
- `app/main.py` — `app.version="0.1.0"`, `/v1/update/channel` placeholder GET endpoint

**Yeni dosyalar (014):**
- `app/api/update.py` — check/changelog/apply endpoint'leri
- `app/update/{__init__,manifest,applier}.py` — manifest fetch + version compare + apply trigger
- `app/health/__init__.py` + `app/health/monitor.py` — 60s cron loop
- `app/cascade/persist.py` — breaker state save/restore
- `app/mcp/tools/update_tools.py` — 3 yeni MCP tool
- `infra/provider-configs/{anthropic,groq,cerebras,gemini,cohere,cloudflare}.yaml` — 6 config
- `app/providers/configs.py` — YAML loader + registry override
- `infra/watchdog/{scanner,alerter,cron.py}` — iskelet (deploy doc'u)
- 7 yeni test dosyası

**Patch'lenecek dosyalar:**
- `app/api/stream.py` — `_build_orchestrator` real, `update-available` event ekle
- `app/main.py` — update_router register + lifespan'de health monitor task + breaker restore + provider configs load
- `app/cascade/breaker.py` — async save() çağrısı record_failure/record_success sonrasında
- `app/static/panel/index.html` + `panel.js` + `panel.css` — update banner UI
- `app/mcp/server.py` — update_tools register
- `tests/test_tools_count.py` — 93 → 96 + 3 must_have

## Beklenen Çıktı

### A. Update Channel — Endpoints + Manifest

**Manifest formatı** (örnek `https://abs.automatiabcn.com/releases/manifest.json`):

```json
{
  "current_version": "0.2.0",
  "released_at": "2026-04-30T00:00:00Z",
  "channel": "stable",
  "min_version": "0.1.0",
  "critical": false,
  "changelog_url": "https://abs.automatiabcn.com/releases/0.2.0",
  "changelog_summary": "RAG hybrid + ML persona training + 2 new MCP tools",
  "docker_image": "ghcr.io/automatia/abs-backend:0.2.0",
  "breaking": false
}
```

**Yeni dosya** `app/update/manifest.py` (~110 satır):

```python
"""Remote release manifest fetch + version compare."""
from __future__ import annotations
import json
import logging
import time
from pathlib import Path
from typing import Any, Dict, Optional
import httpx
from app.config import settings

logger = logging.getLogger(__name__)

CACHE_TTL = 6 * 3600  # 6 saat


def _cache_path() -> Path:
    p = Path(settings.data_dir) / "update_cache.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def _read_cache() -> Optional[Dict[str, Any]]:
    p = _cache_path()
    if not p.is_file():
        return None
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
        if time.time() - d.get("fetched_at", 0) > CACHE_TTL:
            return None
        return d.get("manifest")
    except Exception:
        return None


def _write_cache(manifest: Dict[str, Any]) -> None:
    p = _cache_path()
    payload = {"fetched_at": time.time(), "manifest": manifest}
    p.write_text(json.dumps(payload), encoding="utf-8")


async def fetch_manifest(force: bool = False) -> Dict[str, Any]:
    """Cache-aware manifest fetch."""
    if not force:
        cached = _read_cache()
        if cached:
            return cached
    if not settings.update_manifest_url:
        return {"error": "update_manifest_url tanımlı değil"}
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            r = await client.get(settings.update_manifest_url)
        if r.status_code >= 400:
            return {"error": f"manifest fetch {r.status_code}"}
        manifest = r.json()
    except Exception as exc:
        logger.warning("manifest fetch failed: %s", exc)
        return {"error": str(exc)[:200]}
    _write_cache(manifest)
    return manifest


def compare_versions(current: str, latest: str) -> int:
    """Semver-lite compare. -1 current<latest, 0 eşit, 1 current>latest."""
    def _parse(v: str) -> tuple:
        return tuple(int(x) for x in v.split(".")[:3])
    try:
        a, b = _parse(current), _parse(latest)
        return (a > b) - (a < b)
    except Exception:
        return 0


def update_state(manifest: Dict[str, Any], current_version: str) -> Dict[str, Any]:
    """current vs latest karşılaştırma → state."""
    if "error" in manifest:
        return {"state": "unknown", "error": manifest["error"], "current": current_version}
    latest = manifest.get("current_version", current_version)
    cmp = compare_versions(current_version, latest)
    state = "current" if cmp >= 0 else ("critical" if manifest.get("critical") else "available")
    return {
        "state": state,  # current | available | critical | unknown
        "current": current_version,
        "latest": latest,
        "released_at": manifest.get("released_at"),
        "changelog_url": manifest.get("changelog_url"),
        "changelog_summary": manifest.get("changelog_summary"),
        "critical": manifest.get("critical", False),
        "breaking": manifest.get("breaking", False),
    }
```

**Yeni dosya** `app/update/applier.py` (~70 satır):

```python
"""Update apply — docker-compose pull + restart trigger.

NOT: Backend container'ı kendi-kendini restart edemez. Bu fonksiyon sadece
host'ta `docker compose pull` çalıştırır + `should_restart=True` flag yazar.
Müşteri/cron host-side `docker compose up -d` çalıştırarak finalize eder.
"""
from __future__ import annotations
import json
import logging
import shutil
import subprocess
import time
from pathlib import Path
from typing import Dict
from app.config import settings

logger = logging.getLogger(__name__)


def _flag_path() -> Path:
    p = Path(settings.data_dir) / "update_pending.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def docker_available() -> bool:
    return shutil.which("docker") is not None


async def trigger_pull() -> Dict:
    """Docker compose pull (host'ta). Container içinden çalışmaz; bu fonksiyon
    sadece host volume'una bayrak yazar — host-side cron veya systemd unit
    `pending` flag'ini görüp pull+up çalıştırır."""
    flag = _flag_path()
    payload = {"requested_at": time.time(), "status": "pending"}
    flag.write_text(json.dumps(payload), encoding="utf-8")
    return payload


def pending_status() -> Dict:
    flag = _flag_path()
    if not flag.is_file():
        return {"status": "none"}
    try:
        return json.loads(flag.read_text(encoding="utf-8"))
    except Exception:
        return {"status": "corrupt"}


def clear_pending() -> bool:
    flag = _flag_path()
    if flag.is_file():
        flag.unlink()
        return True
    return False
```

**Yeni dosya** `app/api/update.py` (~80 satır):

```python
"""Update channel endpoints — check/changelog/apply."""
from __future__ import annotations
from fastapi import APIRouter, Depends, HTTPException
from app.api.auth import current_admin
from app.update.manifest import fetch_manifest, update_state
from app.update.applier import trigger_pull, pending_status, clear_pending

router = APIRouter(prefix="/v1/update", tags=["update"])


@router.get("/check")
async def check_update():
    from app.main import app as fastapi_app
    manifest = await fetch_manifest()
    return update_state(manifest, fastapi_app.version)


@router.get("/changelog")
async def changelog(_admin: dict = Depends(current_admin)):
    manifest = await fetch_manifest()
    if "error" in manifest:
        raise HTTPException(status_code=503, detail=manifest["error"])
    return {
        "changelog_url": manifest.get("changelog_url"),
        "summary": manifest.get("changelog_summary"),
        "released_at": manifest.get("released_at"),
        "version": manifest.get("current_version"),
    }


@router.post("/apply")
async def apply_update(_admin: dict = Depends(current_admin)):
    payload = await trigger_pull()
    return {"status": "ok", "pending": payload}


@router.get("/pending")
async def get_pending(_admin: dict = Depends(current_admin)):
    return pending_status()


@router.delete("/pending")
async def clear_pending_endpoint(_admin: dict = Depends(current_admin)):
    return {"cleared": clear_pending()}
```

**Patch** `app/main.py`:
- Mevcut `update_channel_placeholder()` SİL → `update_router` register
- `from app.api import update as update_router; app.include_router(update_router.router)`

**Patch** `app/config.py`:
```python
update_manifest_url: str = "https://abs.automatiabcn.com/releases/manifest.json"
```

**Test** `tests/test_update_channel.py` (~150 satır, 5 test):

1. `test_check_returns_state_current_when_versions_match`: mock manifest `current_version="0.1.0"` + app.version="0.1.0" → state="current".
2. `test_check_returns_available_when_higher_version`: manifest "0.2.0" → state="available".
3. `test_check_returns_critical_when_critical_flag`: manifest "0.2.0" + `critical:true` → state="critical".
4. `test_apply_writes_pending_flag`: POST `/v1/update/apply` (admin auth) → `data_dir/update_pending.json` var.
5. `test_compare_versions_handles_malformed`: `compare_versions("0.1", "abc")` → 0 (no exception).

### B. Provider Configs YAML

**Yeni klasör** `infra/provider-configs/`. 6 dosya:

`anthropic.yaml`:
```yaml
provider: anthropic
display_name: Anthropic Claude
homepage: https://www.anthropic.com/
docs: https://docs.claude.com/
models:
  - alias: claude-haiku
    id: claude-haiku-4-5-20251001
    context: 200000
    pricing_per_mtok_input: 1.0
    pricing_per_mtok_output: 5.0
    deprecated: false
  - alias: claude-sonnet
    id: claude-sonnet-4-6
    context: 200000
    pricing_per_mtok_input: 3.0
    pricing_per_mtok_output: 15.0
    deprecated: false
  - alias: claude-opus
    id: claude-opus-4-7
    context: 200000
    pricing_per_mtok_input: 15.0
    pricing_per_mtok_output: 75.0
    deprecated: false
free_tier: false
rate_limit: tier-based
```

`groq.yaml`, `gemini.yaml`, `cerebras.yaml`, `cohere.yaml`, `cloudflare.yaml` benzer formatta. Her biri `models[]` listesi içerir.

**Yeni dosya** `app/providers/configs.py` (~90 satır):

```python
"""Provider config YAML loader — boot'ta registry'ye apply."""
from __future__ import annotations
import logging
from pathlib import Path
from typing import Dict, List
import yaml

logger = logging.getLogger(__name__)

_PROVIDER_CONFIGS_DIR = Path(__file__).resolve().parents[2] / ".." / "infra" / "provider-configs"
# core/backend/app/providers/configs.py → ../../../infra/provider-configs/

_loaded: Dict[str, dict] = {}


def load_all(directory: Path | None = None) -> Dict[str, dict]:
    """Tüm *.yaml dosyalarını oku, dict döndür."""
    d = directory or _PROVIDER_CONFIGS_DIR
    if not d.is_dir():
        logger.warning("provider configs dir bulunamadı: %s", d)
        return {}
    out: Dict[str, dict] = {}
    for f in sorted(d.glob("*.yaml")):
        try:
            data = yaml.safe_load(f.read_text(encoding="utf-8"))
            if isinstance(data, dict) and "provider" in data:
                out[data["provider"]] = data
        except Exception as exc:
            logger.warning("config parse fail %s: %s", f.name, exc)
    _loaded.update(out)
    return out


def get(provider: str) -> dict | None:
    return _loaded.get(provider)


def get_model_alias(provider: str, alias: str) -> dict | None:
    cfg = _loaded.get(provider) or {}
    for m in cfg.get("models", []):
        if m.get("alias") == alias:
            return m
    return None


def deprecated_models(provider: str) -> List[str]:
    cfg = _loaded.get(provider) or {}
    return [m["id"] for m in cfg.get("models", []) if m.get("deprecated")]
```

**Patch** `app/main.py` lifespan başında:
```python
from app.providers.configs import load_all
load_all()
```

**Test** `tests/test_provider_configs.py` (~110 satır, 4 test):

1. `test_load_all_reads_yaml_files`: tmp_path with 2 yaml files → `len(load_all(tmp_path)) == 2`.
2. `test_get_model_alias`: anthropic.yaml mock → `get_model_alias("anthropic", "claude-haiku")` returns dict.
3. `test_invalid_yaml_logged_not_raised`: tmp_path with broken yaml → load_all returns valid ones, no exception.
4. `test_deprecated_models_filter`: yaml with `deprecated:true` flag → returned in list.

### C. Health Monitor — 60s Loop

**Yeni dosya** `app/health/__init__.py` (re-export) + `app/health/monitor.py` (~140 satır):

```python
"""Provider health monitor — 60s background task.

Her 60s tüm registered provider'lara cheap ping atar, in-memory status dict günceller.
SSE /api/stream/orchestrator event'i bu dict'i okur (random placeholder yerine).
"""
from __future__ import annotations
import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Dict, List
from app.config import settings
from app.providers.registry import get_registry
from app.providers.schemas import ProviderError

logger = logging.getLogger(__name__)

_PING_PROMPT = "ok"
_PING_MAX_TOKENS = 5


@dataclass
class ProviderHealth:
    provider: str
    state: str = "unknown"          # ok | warn | down | unknown
    latency_ms: int = 0
    last_check_at: float = 0.0
    last_error: str | None = None
    consecutive_failures: int = 0


class HealthMonitor:
    def __init__(self, interval_seconds: int = 60) -> None:
        self.interval = interval_seconds
        self._results: Dict[str, ProviderHealth] = {}
        self._task: asyncio.Task | None = None
        self._stop_event = asyncio.Event()

    def snapshot(self) -> List[Dict]:
        return [
            {
                "name": h.provider.title(),
                "state": h.state,
                "latency_ms": h.latency_ms,
                "last_check_at": h.last_check_at,
                "last_error": h.last_error,
            }
            for h in sorted(self._results.values(), key=lambda x: x.provider)
        ]

    async def _ping_one(self, provider_name: str) -> ProviderHealth:
        h = self._results.setdefault(provider_name, ProviderHealth(provider=provider_name))
        h.last_check_at = time.time()
        if not _provider_has_credentials(provider_name):
            h.state = "unknown"
            h.last_error = "no credentials configured"
            return h
        provider = get_registry()[provider_name]
        start = time.monotonic()
        try:
            await provider.call(_PING_PROMPT, max_tokens=_PING_MAX_TOKENS, timeout=8.0)
            h.latency_ms = int((time.monotonic() - start) * 1000)
            h.state = "ok" if h.latency_ms < 3000 else "warn"
            h.last_error = None
            h.consecutive_failures = 0
        except (ProviderError, Exception) as exc:
            h.latency_ms = int((time.monotonic() - start) * 1000)
            h.consecutive_failures += 1
            h.last_error = str(exc)[:200]
            h.state = "down" if h.consecutive_failures >= 2 else "warn"
        return h

    async def _run(self) -> None:
        registry = get_registry()
        while not self._stop_event.is_set():
            tasks = [self._ping_one(n) for n in registry.keys()]
            try:
                await asyncio.gather(*tasks, return_exceptions=True)
            except Exception as exc:
                logger.warning("health monitor cycle fail: %s", exc)
            try:
                await asyncio.wait_for(self._stop_event.wait(), timeout=self.interval)
            except asyncio.TimeoutError:
                pass

    def start(self) -> None:
        if self._task and not self._task.done():
            return
        self._stop_event.clear()
        self._task = asyncio.create_task(self._run())

    async def stop(self) -> None:
        self._stop_event.set()
        if self._task:
            try:
                await asyncio.wait_for(self._task, timeout=5.0)
            except asyncio.TimeoutError:
                self._task.cancel()


def _provider_has_credentials(name: str) -> bool:
    """Cheap credential check — settings'te key set mi?"""
    key_map = {
        "groq": "groq_api_key", "cerebras": "cerebras_api_key",
        "gemini": "gemini_api_key", "cloudflare": "cf_api_token",
        "anthropic": "anthropic_api_key", "ollama": "ollama_url",
    }
    attr = key_map.get(name)
    return bool(getattr(settings, attr, "")) if attr else False


monitor = HealthMonitor()
```

**Patch** `app/main.py` lifespan:
```python
# Health monitor başlat (test mode'da skip)
if os.environ.get("ABS_TEST_MODE") != "1":
    from app.health.monitor import monitor
    monitor.start()
try:
    yield
finally:
    if os.environ.get("ABS_TEST_MODE") != "1":
        await monitor.stop()
```

**Patch** `app/api/stream.py::_build_orchestrator`:
```python
def _build_orchestrator() -> dict:
    from app.health.monitor import monitor
    snap = monitor.snapshot()
    if not snap:
        snap = [{"name": p, "state": "unknown", "latency_ms": 0} for p in _PROVIDERS]
    return {
        "providers": snap,
        "events": [{"t": _now_hms(), "msg": f"{snap[0]['name']} latency {snap[0]['latency_ms']}ms"}],
        "judge": _build_judge_placeholder(),  # judge placeholder 015'te real
    }


def _build_judge_placeholder() -> dict:
    return {
        "score": None,
        "summary": "Judge: henüz veri yok — judge_diff sonrası dolacak.",
        "body": "",
    }
```

**Test** `tests/test_health_monitor.py` (~120 satır, 4 test):

1. `test_snapshot_empty_initially`: HealthMonitor() → snapshot() == [].
2. `test_ping_one_unknown_when_no_credentials`: monkeypatch `_provider_has_credentials` False → state="unknown".
3. `test_ping_one_ok_when_provider_succeeds`: mock provider.call returns response → state="ok", latency_ms set.
4. `test_ping_one_down_after_2_failures`: provider.call raises 2x → consecutive_failures=2 → state="down".

### D. Circuit Breaker Persist

**Yeni dosya** `app/cascade/persist.py` (~80 satır):

```python
"""Circuit breaker state persist — restart sonrası open state korunur."""
from __future__ import annotations
import json
import logging
import time
from pathlib import Path
from typing import Dict
from app.config import settings

logger = logging.getLogger(__name__)


def _state_path() -> Path:
    p = Path(settings.data_dir) / "breaker_state.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def save(states: Dict[str, dict]) -> None:
    """States: {provider: {state, fail_count, opened_at}}."""
    payload = {"saved_at": time.time(), "states": states}
    tmp = _state_path().with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload), encoding="utf-8")
    tmp.replace(_state_path())


def load() -> Dict[str, dict]:
    p = _state_path()
    if not p.is_file():
        return {}
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
        return d.get("states", {})
    except Exception as exc:
        logger.warning("breaker state load fail: %s", exc)
        return {}


def cleanup() -> None:
    p = _state_path()
    if p.is_file():
        p.unlink()
```

**Patch** `app/cascade/breaker.py`:
- `record_failure` ve `record_success` sonunda async `_persist()` çağrısı (debounced — 5 saniye veya 5 değişiklik)
- Class init'te `restore_state()` çağrısı

```python
def restore_state(self) -> int:
    """Disk'ten state yükle."""
    from app.cascade.persist import load
    saved = load()
    restored = 0
    now = self._now()
    for provider, s in saved.items():
        if s.get("state") == "open":
            opened_at_real = s.get("opened_at_real_time", 0)
            elapsed = time.time() - opened_at_real
            if elapsed >= self.reset_timeout_seconds:
                continue  # zaten reset, restore etme
            ps = _ProviderState(
                state="open",
                fail_count=s.get("fail_count", self.fail_threshold),
                opened_at=now,  # monotonic re-baseline
            )
            self._states[provider] = ps
            restored += 1
    return restored


async def _persist(self) -> None:
    """Debounced persist."""
    from app.cascade.persist import save
    snapshot = {}
    for provider, ps in self._states.items():
        if ps.state in ("open", "half_open"):
            snapshot[provider] = {
                "state": ps.state,
                "fail_count": ps.fail_count,
                "opened_at_real_time": time.time(),
            }
    if snapshot:
        save(snapshot)
```

**Test** `tests/test_breaker_persist.py` (~110 satır, 4 test):

1. `test_save_load_roundtrip`: states dict → save → load → eşit.
2. `test_restore_skips_expired_open`: opened_at_real_time = now - 120s, reset=60s → restore atla.
3. `test_restore_keeps_recent_open`: opened_at_real_time = now - 30s → restore eder, state="open".
4. `test_persist_called_after_failure`: monkeypatch save → record_failure 5x → save called.

### E. MCP Tools — update_check / health_status / breaker_status

**Yeni dosya** `app/mcp/tools/update_tools.py` (~70 satır, 3 tool):

```python
"""Update + health + breaker MCP tools (014)."""
from __future__ import annotations
import json
from typing import List
from app.mcp.middleware import with_hooks
from app.mcp.server import mcp_server
from app.mcp.tracking import tracker

REGISTERED_TOOLS: List[str] = []


@mcp_server.tool()
@with_hooks("update_check")
async def update_check() -> str:
    """Remote release manifest → version compare → state."""
    await tracker.bump("update_check")
    from app.update.manifest import fetch_manifest, update_state
    from app.main import app as fastapi_app
    manifest = await fetch_manifest()
    return json.dumps(update_state(manifest, fastapi_app.version), ensure_ascii=False, indent=2)


@mcp_server.tool()
@with_hooks("health_status")
async def health_status() -> str:
    """Tüm provider'ların real-time ping durumu."""
    await tracker.bump("health_status")
    from app.health.monitor import monitor
    return json.dumps({"providers": monitor.snapshot()}, ensure_ascii=False, indent=2)


@mcp_server.tool()
@with_hooks("breaker_status")
async def breaker_status() -> str:
    """Açık circuit breaker listesi (cascade orchestrator)."""
    await tracker.bump("breaker_status")
    from app.cascade.orchestrator import _orchestrator  # singleton
    breaker = getattr(_orchestrator, "breaker", None)
    if not breaker:
        return json.dumps({"states": {}, "note": "breaker yok"}, ensure_ascii=False)
    states = {p: {"state": s.state, "fail_count": s.fail_count} for p, s in breaker._states.items()}
    return json.dumps({"states": states}, ensure_ascii=False, indent=2)


REGISTERED_TOOLS.extend(["update_check", "health_status", "breaker_status"])
```

**Patch** `app/mcp/server.py::register_all_tools` — `from app.mcp.tools import update_tools` import + count.

**Patch** `tests/test_tools_count.py`: 93 → **96**, must_have'a `update_check`, `health_status`, `breaker_status`.

### F. Panel Update Banner

**Patch** `app/static/panel/index.html` — header altında, demo banner sonrasında:
```html
<div id="update-banner" class="update-banner" hidden>
  <span class="update-banner-icon">⬆</span>
  <span class="update-banner-text">
    <strong>Yeni sürüm mevcut: <span id="update-version">—</span></strong>
    <span id="update-summary">—</span>
  </span>
  <button class="update-banner-action" onclick="applyUpdate()">Güncelle</button>
  <button class="update-banner-dismiss" onclick="dismissUpdateBanner()">×</button>
</div>
```

**Patch** `app/static/panel/assets/panel.css`:
```css
.update-banner { background: var(--brand-primary); color: white; padding: 10px 18px; display: flex; gap: 12px; align-items: center; }
.update-banner.update-critical { background: #ef4444; }
.update-banner-action { background: white; color: var(--brand-primary); border: 0; padding: 6px 14px; border-radius: 4px; cursor: pointer; font-weight: 600; }
```

**Patch** `app/static/panel/assets/panel.js`:
```javascript
sse.addEventListener('update-available', (ev) => {
  const d = JSON.parse(ev.data);
  const banner = document.getElementById('update-banner');
  if (!banner) return;
  if (d.state === 'current' || d.state === 'unknown') { banner.hidden = true; return; }
  banner.hidden = false;
  banner.classList.toggle('update-critical', d.state === 'critical');
  document.getElementById('update-version').textContent = d.latest;
  document.getElementById('update-summary').textContent = d.changelog_summary || '';
});

async function applyUpdate() {
  const r = await fetch('/v1/update/apply', { method: 'POST', credentials: 'include' });
  const d = await r.json();
  alert(`Güncelleme istendi. Host'ta docker compose pull && up -d çalıştırın.`);
}

function dismissUpdateBanner() { document.getElementById('update-banner').hidden = true; }
```

**Patch** `app/api/stream.py`:
- `_EVENT_ORDER`'a `"update-available"` ekle (7. event)
- Yeni builder:
```python
async def _build_update_available() -> dict:
    from app.update.manifest import fetch_manifest, update_state
    from app.main import app as fastapi_app
    manifest = await fetch_manifest()
    return update_state(manifest, fastapi_app.version)
```
- `_BUILDERS["update-available"] = _build_update_available` (async)
- `_event_generator` async builder support için patch (mevcut sync `_BUILDERS[ev_name]()` çağrısı async-aware olsun)

**Test** `tests/test_panel_update_banner.py` (~60 satır, 2 test):

1. `test_panel_html_contains_update_banner`: HTML body `id="update-banner"`.
2. `test_panel_js_handles_update_event`: panel.js `addEventListener('update-available'`.

### G. Watchdog Skeleton

**Yeni dosyalar:**

`infra/watchdog/scanner.py` (~80 satır) — provider pricing/changelog scanner iskelet:
```python
"""ABS Central Watchdog — provider pricing + changelog scanner.

Hedef Hetzner $5-10/ay VPS'te cron'da çalışır:
  0 6 * * *  /opt/abs-watchdog/.venv/bin/python -m watchdog.cron

MVP'de: provider docs RSS feed scan + pricing scrape iskelet (httpx+bs4).
Gerçek scrape logic 015+'a (tek tek provider için custom parser).
"""
from __future__ import annotations
import json
import logging
import time
from typing import Dict, List
import httpx

logger = logging.getLogger(__name__)

# Provider docs RSS / changelog endpoint'leri
_FEEDS = {
    "groq": "https://console.groq.com/docs/changelog",
    "anthropic": "https://docs.claude.com/en/release-notes",
    # gemini, cohere, cerebras eklenecek
}


def scan_changelog(provider: str) -> Dict:
    """Stub — gerçek scraping 015'te."""
    return {"provider": provider, "scanned_at": time.time(), "changelog_url": _FEEDS.get(provider), "status": "stub"}


def scan_all() -> List[Dict]:
    return [scan_changelog(p) for p in _FEEDS]
```

`infra/watchdog/alerter.py` (~50 satır) — Discord/email alert iskelet:
```python
"""Discord webhook + email alert — config'ten okur."""
from __future__ import annotations
import os
import httpx


async def send_discord_alert(message: str) -> bool:
    webhook = os.environ.get("WATCHDOG_DISCORD_WEBHOOK", "")
    if not webhook:
        return False
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await client.post(webhook, json={"content": message})
    return r.status_code < 400
```

`infra/watchdog/cron.py` (~30 satır) — entry point:
```python
"""Cron entry point — günde 1 kere scan + alert."""
from .scanner import scan_all
from .alerter import send_discord_alert
import asyncio
import json


async def main():
    results = scan_all()
    print(json.dumps(results, indent=2))
    # Değişiklik tespit edilirse alert
    # MVP: stub — gerçek diff/alert 015'te


if __name__ == "__main__":
    asyncio.run(main())
```

`infra/watchdog/README.md` (~40 satır) — deploy talimatı:
```markdown
# ABS Central Watchdog

Bizim tarafta çalışan cron servis — provider pricing/changelog değişikliklerini günde 1 tarar.

## Deploy (Hetzner VPS, ~$5-10/ay)
1. `python3 -m venv .venv && .venv/bin/pip install httpx pyyaml`
2. crontab: `0 6 * * * cd /opt/abs-watchdog && .venv/bin/python -m watchdog.cron`
3. `WATCHDOG_DISCORD_WEBHOOK=https://...` env

## MVP scope
- Stub'lar mevcut (scanner.py, alerter.py)
- Gerçek scrape 015+'a
- Müşteriye etki YOK — sadece bizim tarafta uyarı
```

**Test** `tests/test_watchdog_skeleton.py` (~40 satır, 2 test):

1. `test_scan_all_returns_list`: `scan_all()` → list, len > 0.
2. `test_alerter_no_webhook_returns_false`: `WATCHDOG_DISCORD_WEBHOOK` boş → `send_discord_alert("test")` → False.

(Watchdog backend container'ında çalışmaz — bu yüzden import path tricky. Test'te `sys.path.insert(0, str(Path("infra"))` veya conditional import.)

## Kısıtlar

- **Mevcut 194 test korunmalı.**
- **Health monitor `ABS_TEST_MODE=1` iken başlamasın** — testler asyncio task'larıyla çakışmasın.
- **Breaker persist `data_dir/breaker_state.json` testlerde tmp_path** ile izole.
- **Manifest fetch testlerde mock** (`respx` veya `httpx.MockTransport`) — gerçek HTTP yok.
- **Update apply CONTAINER İÇİNDE docker compose pull ÇALIŞTIRMAZ** — sadece flag yazar. Host-side cron veya systemd unit pickup eder. Bu kararı `summary.md`'de açık not.
- **Provider configs path:** `infra/provider-configs/` (proje root'tan), Docker container'da `/app/provider-configs` olarak copy edilebilir veya sadece dev mode'da read.
- **Watchdog `infra/watchdog/`** backend container'ında **çalışmaz** — ayrı VPS deploy'a uygun.
- **pytest 215+ veya 213+ skip** zorunlu.
- **Freeze AKTIF** — sadece `/Users/eneseserkan/Main/abs-server-product` içinde edit.

## Adımlar (Worker Claude için)

### 1. Önkoşul (5 dk)
```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                       # 194 passed + 2 skipped
ls app/cascade/ app/api/                                  # mevcut altyapı
```

### 2. Modul A — Update Channel (60 dk)
1. `app/config.py` patch — `update_manifest_url`
2. `app/update/__init__.py` (re-export)
3. `app/update/manifest.py` (fetch + cache + compare + state)
4. `app/update/applier.py` (trigger_pull + pending_status + clear)
5. `app/api/update.py` (5 endpoint)
6. `app/main.py` patch — placeholder sil + update_router register
7. `tests/test_update_channel.py` (5 test)
8. `pytest tests/test_update_channel.py -v` → 5 PASS

### 3. Modul B — Provider Configs (40 dk)
1. `infra/provider-configs/` 6 yaml dosya (anthropic, groq, gemini, cerebras, cohere, cloudflare)
2. `app/providers/configs.py` (loader)
3. `app/main.py` lifespan başında `load_all()`
4. `tests/test_provider_configs.py` (4 test)
5. `pytest tests/test_provider_configs.py -v` → 4 PASS

### 4. Modul C — Health Monitor (45 dk)
1. `app/health/__init__.py` + `app/health/monitor.py`
2. `app/main.py` lifespan — `monitor.start()` + `monitor.stop()` (test_mode skip)
3. `app/api/stream.py` patch — `_build_orchestrator` real, `_build_judge_placeholder`
4. `tests/test_health_monitor.py` (4 test, monkeypatch provider.call)
5. `pytest tests/test_health_monitor.py tests/test_stream_real_data.py -v` → mevcut + yeni hepsi yeşil

### 5. Modul D — Breaker Persist (40 dk)
1. `app/cascade/persist.py`
2. `app/cascade/breaker.py` patch — `restore_state` + `_persist`
3. `tests/test_breaker_persist.py` (4 test)
4. `pytest tests/test_breaker_persist.py -v` → 4 PASS

### 6. Modul E — MCP Tools (20 dk)
1. `app/mcp/tools/update_tools.py` (3 tool)
2. `app/mcp/server.py` Read → tam Write override (update_tools import + count)
3. `tests/test_tools_count.py` patch (93 → 96)
4. `pytest tests/test_tools_count.py -v` → 2 PASS

### 7. Modul F — Panel Banner (25 dk)
1. `app/static/panel/index.html` patch — `update-banner` div
2. `app/static/panel/assets/panel.css` patch — banner styles
3. `app/static/panel/assets/panel.js` patch — SSE handler + applyUpdate()
4. `app/api/stream.py` patch — `update-available` event + async builder support
5. `tests/test_panel_update_banner.py` (2 test)
6. `pytest tests/test_panel_update_banner.py -v` → 2 PASS

### 8. Modul G — Watchdog Skeleton (15 dk)
1. `infra/watchdog/{scanner,alerter,cron}.py` + `README.md`
2. `tests/test_watchdog_skeleton.py` (2 test, sys.path manipulation)
3. `pytest tests/test_watchdog_skeleton.py -v` → 2 PASS

### 9. Tam Test Suite (5 dk)
```bash
.venv/bin/pytest -q
# 215+ passed (+2 skipped from 013)
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 96
```

### 10. Live MCP Smoke (15 dk)

uvicorn boot + `claude mcp add abs-014` + 4 kanıt JSON `/tmp/abs-014-smoke/evidence/`:

- **01** `update_check` → `{state:"unknown", error:"..."}` (manifest URL erişilemez normal — graceful) veya gerçek state
- **02** `health_status` → `{providers:[]}` boş (test mode lifespan skip ettiği için monitor başlatılmamış olabilir; uvicorn live mode'da dolu)
- **03** `breaker_status` → `{states:{}}` boş
- **04** GET `/v1/update/check` REST karşılaştırma

### 11. Tamamlama
1. `_agent-tasks/completed/014-update-channel-watchdog.md` taşı
2. `014-update-channel-watchdog-summary.md` yaz:
   - 7 modül + dosya listesi
   - Test sonuçları (194 → 215+)
   - 4 smoke kanıtı
   - Notlar Planlayıcıya (manifest URL gerçek değil, watchdog deploy 015+'a, vb.)

## Doğrulama (Worker fail-fast)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pip install pyyaml          # zaten 013'te kurulu olmalı
.venv/bin/pytest -q                                              # 215+ passed
.venv/bin/pytest tests/test_tools_count.py -v                    # 96 guard
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 96
.venv/bin/python -c "from app.providers.configs import load_all; print(len(load_all()))"
# 6
.venv/bin/python -c "from app.health.monitor import monitor; print(monitor.snapshot())"
# []
```

## Notlar Planlayıcıya (Worker doldursun)

- **`update_manifest_url` placeholder** `https://abs.automatiabcn.com/releases/manifest.json` — domain henüz live değil. Müşteri override edebilir (`ABS_UPDATE_MANIFEST_URL` env). MVP'de "unknown" state graceful.
- **Update apply container restart edemez** — `update_pending.json` flag yazar; host-side `docker compose pull && up -d` veya systemd unit pickup eder. Bu mimari kararı operations doc'a (`docs/operations.md`) eklenmeli (015).
- **Watchdog Hetzner deploy** 015 kapsamında. Bu task sadece iskelet; gerçek pricing scrape provider başına custom parser ister.
- **Health monitor 60s interval ABS_HEALTH_INTERVAL env** ile config edilebilir mi 015'te?
- **Provider configs YAML schema validation** — şu an basit parse, jsonschema ile sıkı validate 015+'a.
- **Manifest signature verification** (RS256 imzalı manifest) — şu an plaintext JSON, supply-chain attack açık. Production'da CRITICAL — 015'te ekle.
- **Breaker persist 5 değişiklikte 1 yaz** — debounce eksik, her record_failure persist çağırır. Production'da yüksek RPS varsa optimize.
- **Update banner localStorage dismiss** — daha kalıcı (tarayıcı session) için 015'te `dismissed_until_version` flag düşünülebilir.

## Kapsam Dışı (015+'a)

- Watchdog production deploy (Hetzner cron, real scrape parsers)
- Manifest signature verification (RS256)
- Update breaking-change migration script
- Panel `cache_stats`, `today_usd`, `learnings_count`, `symbol_graph` real data (placeholder kalan)
- Provider configs JSON schema validation
- Health monitor interval tuning + alert webhook
- Update auto-apply (cron-driven) — şu an sadece manuel onay
- Multi-channel release tracks (stable/beta/canary)
