# Task 015 — Panel Placeholder → Real + Manifest Signature + Watchdog Deploy Doc

**Tahmini süre:** 3-4 saat (5 modül — cache real + cost real + learnings + signature + deploy doc)
**Önkoşul:** 014 tamam (96 MCP tool, 223 passed + 2 skipped)

## Bağlam

Panel SSE event'leri çoğu **gerçek data verir** (tracker.snapshot, workflow.stats, license-status, orchestrator real ping). Hâlâ random/placeholder olan 4 alan + 1 supply-chain güvenlik açığı kaldı:

1. **`cache_stats` MCP tool** dummy 0/0 döndürüyor — `app/cascade/cache.py::SemanticCache` `_hits`/`_misses` counter mevcut ama cascade orchestrator cache'i kullanmıyor (hot path'e bağlı değil)
2. **`_build_budget.today_usd` random** — gerçek değil, tahmini Anthropic maliyeti
3. **`_build_budget.learnings_count` random** — Claude Code bugfix dersleri kaydedilmiyor
4. **`_build_budget` projected_monthly_usd** — tahmini, gerçek tracker × pricing yok
5. **Manifest fetch 014'te imzalı değil** — supply-chain attack açık (saldırgan DNS hijack ile sahte manifest yayınlayıp `update apply` tetikleyebilir)
6. **Watchdog deploy edilmedi** — Hetzner $5/ay VPS cron, Discord webhook setup talimatı yok

015 bu 6 boşluğu kapatır:

1. **Cascade cache integration** — orchestrator her provider çağrısı öncesi `default_cache.get(key)` + sonrası `set` → real hit/miss
2. **Daily cost real** — `tracker.snapshot()` × `provider_configs` pricing → günlük tahmini maliyet
3. **Learnings system** — `data_dir/learnings.jsonl` append, hook tetiklemeli (delegate_nudge "iyi karar" sinyali ile)
4. **Manifest RS256 signature** — release manifest imzalı, fetch sonrası verify, bizim tarafta `infra/manifest-keys/private.pem` (gizli) + müşteri tarafında `app/update/manifest_pubkey.pem` (gömülü)
5. **Watchdog deploy doc** — `docs/operations.md` § watchdog setup + `infra/watchdog/deploy.sh` Hetzner kurulum script
6. **MCP tools** — `daily_cost`, `learnings_recent`, `learnings_log` (3 yeni tool)

**Tool sayısı hedefi:** 96 → **99 tool** (+3).
**Test sayısı hedefi:** 223 → **~245+ test** (+22: 4 cache integration, 4 daily cost, 4 learnings, 4 manifest sig, 3 mcp, 3 panel real data).

## Giriş (Mevcut Durum — Worker doğrulasın)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                       # 223 passed + 2 skipped
.venv/bin/python -c "from app.cascade.cache import SemanticCache; print(SemanticCache().stats())"
# {'hits':0, 'misses':0, 'entries':0, 'hit_rate_pct':0.0}
.venv/bin/python -c "from app.providers.configs import load_all; cfg=load_all(); print(cfg['groq']['models'][0])"
# {'alias':'...', 'pricing_per_mtok_input':0.X, ...}
.venv/bin/python -c "from app.mcp.tracking import tracker; print(tracker.snapshot())"
# {} (boş veya minimal)
```

**Mevcut altyapı:**
- `app/cascade/cache.py::SemanticCache` — `get`/`set`/`stats` + `_hits`/`_misses` counter
- `app/cascade/orchestrator.py` — provider cascade chain (cache integration eksik)
- `app/providers/configs.py::load_all()` — 6 YAML config (014'te yazıldı)
- `app/mcp/tracking.py::tracker.snapshot()` — tool kullanım counter
- `app/api/stream.py::_build_budget` — random `today_usd`/`learnings_count`
- `app/update/manifest.py::fetch_manifest` — plaintext JSON fetch (014'te yazıldı)

**Yeni dosyalar (015):**
- `app/learnings/__init__.py` + `app/learnings/store.py` — JSONL append/read
- `app/billing/__init__.py` + `app/billing/cost_estimator.py` — tracker × pricing → günlük maliyet
- `app/update/signature.py` — RS256 verify
- `app/update/manifest_pubkey.pem` — public key (worker generate edip dosyaya yazacak; private key sadece bizim tarafta)
- `app/mcp/tools/billing_tools.py` (3 tool: daily_cost, learnings_recent, learnings_log)
- 6 yeni test dosyası

**Patch'lenecek dosyalar:**
- `app/cascade/orchestrator.py` — cache integration (get before call, set after success)
- `app/api/stream.py::_build_budget` — real cost + real learnings count
- `app/update/manifest.py::fetch_manifest` — `verify_signature` çağrısı
- `app/hooks/delegate_nudge.py` — başarılı delegasyon sonrası `learnings.log()` çağrısı (opsiyonel sinyal)
- `docs/operations.md` — watchdog setup section
- `infra/watchdog/deploy.sh` — Hetzner kurulum script
- `app/mcp/server.py` — billing_tools register
- `tests/test_tools_count.py` — 96 → 99 + 3 must_have

## Beklenen Çıktı

### A. Cascade Cache Integration

**Patch** `app/cascade/orchestrator.py`:

Mevcut `cascade_call(prompt, providers, model)` fonksiyonu — her provider denemeden ÖNCE cache'e bak, başarılı sonrası cache'e yaz.

```python
from app.cascade.cache import SemanticCache, prompt_hash

# Module-level singleton — `default_cache` mevcut module'da
# 015 — orchestrator'a inject et

class CascadeOrchestrator:
    def __init__(self, ..., cache: Optional[SemanticCache] = None):
        # ... mevcut
        from app.cascade.cache import default_cache
        self._cache = cache or default_cache

    async def call(self, prompt: str, providers: list[str], model: str = "") -> ProviderResponse:
        cache_key = prompt_hash(prompt, model)
        cached = await self._cache.get(cache_key)
        if cached:
            return cached  # ProviderResponse instance, type hint guard
        # mevcut cascade akışı...
        for p_name in providers:
            if not await self.breaker.allow(p_name):
                continue
            try:
                resp = await provider.call(prompt, model=model)
                await self._cache.set(cache_key, resp)
                await self.breaker.record_success(p_name)
                return resp
            except (ProviderError, Exception) as exc:
                # ... mevcut
```

**Patch** `app/mcp/tools/system_extras.py::cache_stats`:
- Mevcut: `default_cache.stats()` zaten doğru — sadece data akışı şimdi real olacak.

**Test** `tests/test_cache_integration.py` (~110 satır, 4 test):

1. `test_cache_miss_first_call`: `cascade.call("foo", ["mock"])` 1x → `stats.misses==1`, `hits==0`.
2. `test_cache_hit_second_call_same_prompt`: 2x aynı prompt → `hits==1, misses==1`.
3. `test_cache_different_prompts_no_hit`: "foo" + "bar" → `misses==2, hits==0`.
4. `test_cache_ttl_expiry`: monkeypatch `ttl_seconds=0.1` + sleep 0.2 → 2. çağrı miss.

### B. Daily Cost Estimation

**Yeni dosya** `app/billing/__init__.py` (re-export) + `app/billing/cost_estimator.py` (~120 satır):

```python
"""Tracker × provider_configs pricing → günlük tahmini maliyet."""
from __future__ import annotations
import logging
import time
from typing import Dict, List
from app.mcp.tracking import tracker
from app.providers.configs import load_all

logger = logging.getLogger(__name__)


def _today_window_seconds() -> float:
    return 86400.0  # 24h


def _model_to_provider(model: str) -> tuple[str, str] | None:
    """Tool name'inden provider+alias çıkar.

    Tracker tool isimleri: `ask_gptoss`, `ask_kimi`, `ask_haiku`, ...
    Bu isimler -> alias map (provider_configs içinde alias=...).
    """
    # Basit eşleme — provider_configs'tan dynamic build
    cfg = load_all()
    for prov, data in cfg.items():
        for m in data.get("models", []):
            alias = m.get("alias", "")
            # ask_<alias>, ask_<provider>, ask_<short-id>
            for candidate in (f"ask_{alias}", f"ask_{m.get('id','').replace('-','_').lower()}"):
                if model == candidate:
                    return prov, alias
    return None


def estimate_daily_cost() -> Dict:
    """Tracker.snapshot()'tan son 24h'lik tool çağrılarını + provider_configs pricing × token sayıları."""
    snap = tracker.snapshot()
    cfg = load_all()
    total_usd = 0.0
    by_provider: Dict[str, float] = {}
    breakdown: List[Dict] = []
    for tool_name, usage in snap.items():
        match = _model_to_provider(tool_name)
        if not match:
            continue
        provider, alias = match
        # Provider model bilgisi
        model = next((m for m in cfg[provider].get("models", []) if m.get("alias") == alias), None)
        if not model:
            continue
        # Tracker'da token sayısı yok şu an — sadece count_24h. Ortalama 1500 tok/call varsay
        avg_tokens_per_call = 1500
        in_tok = usage["count_24h"] * avg_tokens_per_call * 0.3   # %30 input
        out_tok = usage["count_24h"] * avg_tokens_per_call * 0.7  # %70 output
        cost_in = (in_tok / 1_000_000) * float(model.get("pricing_per_mtok_input", 0))
        cost_out = (out_tok / 1_000_000) * float(model.get("pricing_per_mtok_output", 0))
        cost = round(cost_in + cost_out, 4)
        total_usd += cost
        by_provider[provider] = round(by_provider.get(provider, 0.0) + cost, 4)
        breakdown.append({
            "tool": tool_name, "provider": provider, "model_alias": alias,
            "calls_24h": usage["count_24h"], "estimated_usd": cost,
        })
    return {
        "today_usd": round(total_usd, 2),
        "projected_monthly_usd": round(total_usd * 30, 2),
        "by_provider": by_provider,
        "breakdown": sorted(breakdown, key=lambda x: -x["estimated_usd"])[:10],
        "estimated_at": time.time(),
        "note": "Token sayısı tahmini (1500 avg, 30/70 split). 016+ gerçek token tracking.",
    }
```

**Patch** `app/api/stream.py::_build_budget`:
```python
def _build_budget() -> dict:
    from app.billing.cost_estimator import estimate_daily_cost
    cost = estimate_daily_cost()
    from app.workflow import stats as workflow_stats, list_workflows
    wf = workflow_stats()
    recent = list_workflows(limit=5)
    from app.learnings.store import recent_count  # 015-C
    return {
        "today_usd": cost["today_usd"],
        "projected_monthly_usd": cost["projected_monthly_usd"],
        "learnings_count": recent_count(window_days=30),
        "workflow": {
            "summary": f"{wf.get('by_status', {}).get('ok', 0)}/{wf.get('total_workflows', 0)} ok",
            "items": [
                {"id": w["id"][:8], "status": w["status"], "step": w["type"]}
                for w in recent
            ],
        },
    }
```

**Test** `tests/test_cost_estimator.py` (~120 satır, 4 test):

1. `test_estimate_returns_zero_when_no_usage`: tracker boş → `today_usd==0.0`.
2. `test_estimate_with_one_tool_call`: monkeypatch tracker → ask_gptoss 10 calls → `today_usd > 0`, breakdown[0]["tool"]=="ask_gptoss".
3. `test_unknown_tool_skipped`: tracker'da `ask_foobar` 100 calls → `today_usd==0.0` (provider_configs'ta yok).
4. `test_breakdown_sorted_by_cost`: 2 tool, biri büyük tok → büyük olan ilk sırada.

### C. Learnings JSONL Store

**Yeni dosya** `app/learnings/__init__.py` (re-export) + `app/learnings/store.py` (~120 satır):

```python
"""Learnings — bugfix/iyi-karar dersleri JSONL append-only.

Format:
  {ts, category: 'bugfix'|'delegation'|'arch'|'security', lesson, source, project, hash}

Hook'lar (delegate_nudge başarılı delegation tespit edince) veya manuel API
(`/v1/learnings`) üzerinden eklenir. Panel SSE budget event'inde count görünür.
"""
from __future__ import annotations
import hashlib
import json
import logging
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
from app.config import settings

logger = logging.getLogger(__name__)

_VALID_CATEGORIES = {"bugfix", "delegation", "arch", "security", "perf", "ux"}


def _path() -> Path:
    p = Path(settings.data_dir) / "learnings.jsonl"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def _hash_lesson(lesson: str) -> str:
    return hashlib.sha256(lesson.encode("utf-8")).hexdigest()[:12]


def log(
    category: str,
    lesson: str,
    *,
    source: str = "manual",
    project: Optional[str] = None,
) -> Optional[str]:
    """Yeni learning ekle. Aynı hash 24h içinde 2x → skip."""
    if category not in _VALID_CATEGORIES:
        return None
    if not lesson.strip():
        return None
    h = _hash_lesson(lesson)
    # Idempotency: son 50 entry'de aynı hash varsa skip
    for entry in recent(limit=50):
        if entry.get("hash") == h and (time.time() - entry.get("ts", 0)) < 86400:
            return None
    entry = {
        "ts": time.time(),
        "category": category,
        "lesson": lesson[:500],
        "source": source,
        "project": project,
        "hash": h,
    }
    try:
        with open(_path(), "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception as exc:
        logger.warning("learnings log fail: %s", exc)
        return None
    return h


def recent(limit: int = 20) -> List[Dict[str, Any]]:
    p = _path()
    if not p.is_file():
        return []
    try:
        lines = p.read_text(encoding="utf-8").splitlines()[-limit:]
        return [json.loads(line) for line in lines if line.strip()]
    except Exception:
        return []


def recent_count(window_days: int = 30) -> int:
    cutoff = time.time() - window_days * 86400
    return sum(1 for e in recent(limit=2000) if e.get("ts", 0) >= cutoff)


def stats() -> Dict[str, Any]:
    entries = recent(limit=2000)
    by_cat: Dict[str, int] = {}
    for e in entries:
        c = e.get("category", "unknown")
        by_cat[c] = by_cat.get(c, 0) + 1
    return {
        "total": len(entries),
        "by_category": by_cat,
        "last_30d": recent_count(window_days=30),
        "last_7d": recent_count(window_days=7),
    }
```

**Patch (opsiyonel)** `app/hooks/delegate_nudge.py`:
- Başarılı bir delegation tespit edilince (mevcut nudge'ın "ASK_KIMI ile yaptın - iyi karar" sinyali olursa) `learnings.log("delegation", "...", source="hook")` çağrısı.
- Bu basit bir 5-satır ekleme; eksik kalsa olur — manuel API yeterli.

**Test** `tests/test_learnings_store.py` (~110 satır, 4 test):

1. `test_log_creates_jsonl_entry`: `log("bugfix", "X")` → file var, line valid JSON, hash returned.
2. `test_log_idempotent_within_24h`: `log("bugfix", "Y")` 2x → 2. çağrı None döner, file 1 satır.
3. `test_recent_count_window_days`: 3 entry (1 today, 1 5d ago, 1 35d ago) → `recent_count(30)==2`.
4. `test_invalid_category_rejected`: `log("foo", "Z")` → None, file boş.

### D. Manifest RS256 Signature

**Yeni dosya** `app/update/signature.py` (~110 satır):

```python
"""Release manifest RS256 signature verification.

Tasarım:
  - Bizim taraf (release pipeline): private.pem ile manifest.json'u imzala,
    çıktı `manifest.json.sig` (Base64 RS256).
  - Müşteri taraf: app/update/manifest_pubkey.pem ile verify.
  - Manifest URL'i fetch ederken `manifest.json` + `manifest.json.sig` ikisi de çekilir.
  - Fail-closed: imza yok veya doğrulanamazsa update_state(state='unknown', error='signature').
"""
from __future__ import annotations
import base64
import logging
from pathlib import Path
from typing import Optional
import httpx
from app.config import settings

logger = logging.getLogger(__name__)


def _pubkey_path() -> Path:
    return Path(__file__).parent / "manifest_pubkey.pem"


def verify_manifest(manifest_bytes: bytes, signature_b64: str) -> bool:
    """RS256 verify. False = invalid (fail-closed)."""
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
    except ImportError:
        logger.warning("cryptography paketi yok — manifest signature skip")
        return False
    pubkey_path = _pubkey_path()
    if not pubkey_path.is_file():
        logger.warning("manifest pubkey yok: %s", pubkey_path)
        return False
    try:
        pubkey = serialization.load_pem_public_key(pubkey_path.read_bytes())
        signature = base64.b64decode(signature_b64)
        pubkey.verify(
            signature,
            manifest_bytes,
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
        return True
    except Exception as exc:
        logger.warning("manifest signature verify fail: %s", exc)
        return False


async def fetch_signature(manifest_url: str) -> Optional[str]:
    """Manifest URL'inin yanındaki .sig dosyasını çek."""
    sig_url = manifest_url + ".sig"
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            r = await client.get(sig_url)
        if r.status_code >= 400:
            return None
        return r.text.strip()
    except Exception as exc:
        logger.warning("signature fetch fail: %s", exc)
        return None
```

**Patch** `app/update/manifest.py::fetch_manifest`:
- Cache miss path'inde manifest fetch sonrası: `signature_b64 = await fetch_signature(url)` → `verify_manifest(manifest_raw_bytes, signature_b64)` → fail ise `manifest = {"error": "signature_invalid", ...}`.
- Cache geçerliyse signature tekrar verify edilmez (cache TTL içinde güven).
- `settings.update_signature_required: bool = True` (default), False ise verify skip (dev mode).

**Patch** `app/config.py`:
```python
update_signature_required: bool = True   # 015 — manifest RS256 verify zorunlu
```

**Yeni dosya** `app/update/manifest_pubkey.pem` — placeholder. Worker `infra/scripts/generate_manifest_keys.sh` ile RSA 4096 generate eder, public key'i bu dosyaya yazar. Private key `/tmp/abs-manifest-private.pem`'a yazıp **summary.md'ye yazma** (kullanıcı saklayacak).

**Yeni dosya** `infra/scripts/generate_manifest_keys.sh` (~30 satır):
```bash
#!/usr/bin/env bash
# ABS Manifest signing keys generator (TEK SEFER — release pipeline kurulumu).
set -euo pipefail
OUT_DIR="${OUT_DIR:-./manifest-keys}"
mkdir -p "$OUT_DIR"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$OUT_DIR/private.pem"
openssl rsa -pubout -in "$OUT_DIR/private.pem" -out "$OUT_DIR/public.pem"
echo "✓ Generated:"
echo "  Private key (BIZIM, gizli): $OUT_DIR/private.pem"
echo "  Public key:                $OUT_DIR/public.pem"
echo ""
echo "NEXT:"
echo "1. Kopyalayın: cp $OUT_DIR/public.pem core/backend/app/update/manifest_pubkey.pem"
echo "2. Private key'i offline tutun (1Password, hardware token)"
echo "3. Release imzalama: openssl dgst -sha256 -sign private.pem -out manifest.json.sig manifest.json"
```

**Test** `tests/test_manifest_signature.py` (~140 satır, 4 test):

1. `test_verify_returns_false_when_no_pubkey`: monkeypatch `_pubkey_path` -> nonexistent → False.
2. `test_verify_with_valid_signature`: tmp RSA keypair generate, manifest sign + verify → True.
3. `test_verify_with_tampered_manifest`: valid sig + modified manifest → False.
4. `test_fetch_manifest_rejects_unsigned_when_required`: respx mock manifest 200 + signature 404 + `update_signature_required=True` → state="unknown", error contains "signature".

### E. Watchdog Deploy Doc + Script

**Yeni dosya** `infra/watchdog/deploy.sh` (~80 satır):

```bash
#!/usr/bin/env bash
# ABS Central Watchdog deploy — Hetzner CX11 / DO smallest VPS / similar
# Kullanım: ssh root@<vps> 'bash -s' < deploy.sh
set -euo pipefail
INSTALL_DIR="${INSTALL_DIR:-/opt/abs-watchdog}"
WATCHDOG_USER="${WATCHDOG_USER:-watchdog}"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

# 1. User + dirs
id -u "$WATCHDOG_USER" >/dev/null 2>&1 || useradd --system --create-home "$WATCHDOG_USER"
mkdir -p "$INSTALL_DIR"
chown -R "$WATCHDOG_USER:$WATCHDOG_USER" "$INSTALL_DIR"

# 2. Python venv + deps
sudo -u "$WATCHDOG_USER" python3 -m venv "$INSTALL_DIR/.venv"
sudo -u "$WATCHDOG_USER" "$INSTALL_DIR/.venv/bin/pip" install --upgrade pip
sudo -u "$WATCHDOG_USER" "$INSTALL_DIR/.venv/bin/pip" install httpx pyyaml

# 3. Code (kullanıcı git clone veya scp ile yüklemeli)
echo "NEXT: git clone https://github.com/automatia/abs $INSTALL_DIR/src"
echo "      veya scp infra/watchdog/* root@vps:$INSTALL_DIR/src/watchdog/"

# 4. Cron
cat > /etc/cron.d/abs-watchdog <<EOF
# ABS Watchdog — günde 1 kez 06:00 UTC
0 6 * * *  $WATCHDOG_USER  cd $INSTALL_DIR/src && DISCORD_WEBHOOK='$DISCORD_WEBHOOK' .venv/bin/python -m watchdog.cron 2>&1 | logger -t abs-watchdog
EOF
chmod 644 /etc/cron.d/abs-watchdog

# 5. Logrotate
cat > /etc/logrotate.d/abs-watchdog <<EOF
/var/log/abs-watchdog.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF

echo "✓ ABS Watchdog deployed. Test: sudo -u $WATCHDOG_USER cd $INSTALL_DIR/src && .venv/bin/python -m watchdog.cron"
```

**Patch** `docs/operations.md` — yeni bölüm `### Watchdog Deploy (Hetzner)`:
- VPS spec (CX11 €4/ay, 2vCPU 4GB)
- DNS (`watchdog.automatiabcn.com` → A record)
- `bash deploy.sh` (yukarıdaki script)
- Discord webhook URL setup adımı
- Manifest release flow (op-side):
  1. Yeni release hazır
  2. `manifest.json` editle
  3. `openssl dgst -sha256 -sign private.pem -out manifest.json.sig manifest.json`
  4. `aws s3 cp` veya scp ile release sunucusuna yayın
  5. Watchdog cron 06:00'da scan → değişiklik varsa Discord alert

**Patch** `infra/watchdog/README.md` — deploy.sh referansı + manifest signing flow

**Test** — yok (deploy script + doc, runtime test edilmez)

### F. MCP Tools

**Yeni dosya** `app/mcp/tools/billing_tools.py` (~70 satır, 3 tool):

```python
"""Billing + learnings MCP tools (015)."""
from __future__ import annotations
import json
from typing import List, Optional
from app.mcp.middleware import with_hooks
from app.mcp.server import mcp_server
from app.mcp.tracking import tracker

REGISTERED_TOOLS: List[str] = []


@mcp_server.tool()
@with_hooks("daily_cost")
async def daily_cost() -> str:
    """Tracker × provider_configs pricing → günlük tahmini maliyet."""
    await tracker.bump("daily_cost")
    from app.billing.cost_estimator import estimate_daily_cost
    return json.dumps(estimate_daily_cost(), ensure_ascii=False, indent=2)


@mcp_server.tool()
@with_hooks("learnings_recent")
async def learnings_recent(limit: int = 20) -> str:
    """Son N learning kaydı (bugfix/delegation/arch/security/...)."""
    await tracker.bump("learnings_recent")
    from app.learnings.store import recent, stats
    return json.dumps({"recent": recent(limit=limit), "stats": stats()}, ensure_ascii=False, indent=2)


@mcp_server.tool()
@with_hooks("learnings_log")
async def learnings_log(category: str, lesson: str, project: Optional[str] = None) -> str:
    """Manuel learning ekle. category: bugfix|delegation|arch|security|perf|ux."""
    await tracker.bump("learnings_log")
    from app.learnings.store import log
    h = log(category, lesson, source="mcp_tool", project=project)
    return json.dumps({"ok": h is not None, "hash": h}, ensure_ascii=False)


REGISTERED_TOOLS.extend(["daily_cost", "learnings_recent", "learnings_log"])
```

**Patch** `app/mcp/server.py` — `from app.mcp.tools import billing_tools` + count.
**Patch** `tests/test_tools_count.py` — 96 → 99 + 3 must_have.

### G. Panel Real Data Test

**Test** `tests/test_panel_real_data_v2.py` (~80 satır, 3 test):

1. `test_build_budget_uses_real_cost`: monkeypatch `estimate_daily_cost` → `{today_usd: 1.23, ...}` → `_build_budget()['today_usd'] == 1.23`.
2. `test_build_budget_uses_real_learnings`: monkeypatch `recent_count` → 5 → `learnings_count == 5`.
3. `test_cache_stats_tool_returns_real_counter`: cache hit'lerden sonra `cache_stats` → real number, not 0.

## Kısıtlar

- **Mevcut 223 test korunmalı.**
- **`update_signature_required` default True** — production güvenlik. Dev test'te `False` set edilebilir.
- **`manifest_pubkey.pem` repository'de** — bu public key, gömülü olmasında sakınca yok.
- **Cost estimator basit** — token sayısı tracker'da yok, ortalama 1500 tok/call varsayım. 016+ gerçek token tracking için tracker.bump'a tokens_in/out parametre eklenebilir.
- **Learnings idempotency** — aynı hash 24h içinde 2x skip; daha sıkı dedup gerekirse bloom filter.
- **Watchdog deploy.sh test edilmez** — manuel infra script.
- **pytest 245+ veya 243+ skip** zorunlu.
- **Freeze AKTIF.**

## Adımlar (Worker Claude için)

### 1. Önkoşul (5 dk)
```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                       # 223 + 2 skipped
```

### 2. Modul A — Cache Integration (45 dk)
1. `app/cascade/orchestrator.py` patch — cache get/set integration
2. `tests/test_cache_integration.py` (4 test, mock provider)
3. `pytest tests/test_cache_integration.py -v` → 4 PASS

### 3. Modul B — Daily Cost (40 dk)
1. `app/billing/__init__.py` + `app/billing/cost_estimator.py`
2. `app/api/stream.py::_build_budget` patch
3. `tests/test_cost_estimator.py` (4 test)
4. `pytest tests/test_cost_estimator.py -v` → 4 PASS

### 4. Modul C — Learnings Store (35 dk)
1. `app/learnings/__init__.py` + `app/learnings/store.py`
2. (Opsiyonel) `app/hooks/delegate_nudge.py` patch — başarılı delegation log
3. `tests/test_learnings_store.py` (4 test, tmp_path)
4. `pytest tests/test_learnings_store.py -v` → 4 PASS

### 5. Modul D — Manifest Signature (50 dk)
1. `infra/scripts/generate_manifest_keys.sh` çalıştır → `manifest-keys/{private,public}.pem`
2. `cp manifest-keys/public.pem core/backend/app/update/manifest_pubkey.pem`
3. **Private key'i offline saklayın** — repo'ya commit YASAK. summary.md'ye redacted yaz.
4. `app/update/signature.py` (verify + fetch)
5. `app/update/manifest.py` patch — fetch sonrası verify
6. `app/config.py` patch — `update_signature_required`
7. `tests/test_manifest_signature.py` (4 test, tmp keypair)
8. `pytest tests/test_manifest_signature.py -v` → 4 PASS

### 6. Modul E — Watchdog Deploy Doc (15 dk)
1. `infra/watchdog/deploy.sh` (executable)
2. `docs/operations.md` patch — Watchdog Deploy bölümü
3. `infra/watchdog/README.md` patch — deploy + signing flow
4. (Test yok)

### 7. Modul F — MCP Tools (15 dk)
1. `app/mcp/tools/billing_tools.py` (3 tool)
2. `app/mcp/server.py` Read → tam Write override
3. `tests/test_tools_count.py` patch (96 → 99)
4. `pytest tests/test_tools_count.py -v` → 2 PASS

### 8. Modul G — Panel Real Data Tests (15 dk)
1. `tests/test_panel_real_data_v2.py` (3 test)
2. `pytest tests/test_panel_real_data_v2.py -v` → 3 PASS

### 9. Tam Test Suite (5 dk)
```bash
.venv/bin/pytest -q
# 245+ passed (+2 skipped from 013)
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 99
```

### 10. Live MCP Smoke (15 dk)
```bash
mkdir -p /tmp/abs-015-smoke/{data,evidence}
ABS_DATA_DIR=/tmp/abs-015-smoke/data \
ABS_UPDATE_SIGNATURE_REQUIRED=false \
.venv/bin/uvicorn app.main:app --port 8765 &

# 4 kanıt /tmp/abs-015-smoke/evidence/:
# 01: daily_cost MCP → today_usd:0.0 (boş tracker, beklenen)
# 02: learnings_log("bugfix","Test ders") → ok:true, hash returned
# 03: learnings_recent → 1 entry: bugfix
# 04: cache_stats → real counter (uvicorn boot sonrası bazı tool'lar çağrıldıysa hits/misses dolar)
```

### 11. Tamamlama
1. `_agent-tasks/completed/015-panel-real-data-manifest-sig.md` taşı
2. `015-panel-real-data-manifest-sig-summary.md` yaz:
   - 5 modül + dosya listesi
   - Test sonuçları (223 → 245+)
   - Manifest private key durumu (REDACTED, "kullanıcıya verildi")
   - Notlar Planlayıcıya

## Doğrulama (Worker fail-fast)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                                # 245+ passed
.venv/bin/pytest tests/test_tools_count.py -v                      # 99 guard
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"  # 99
.venv/bin/python -c "from app.billing.cost_estimator import estimate_daily_cost; print(estimate_daily_cost())"
.venv/bin/python -c "from app.learnings.store import stats; print(stats())"
test -f app/update/manifest_pubkey.pem && echo "pubkey OK"
test ! -f app/update/manifest_private.pem && echo "private NOT in repo (correct)"
```

## Notlar Planlayıcıya (Worker doldursun)

- **Manifest private key** `manifest-keys/private.pem` — `summary.md`'ye **YAZILMADI**. Kullanıcıya elden teslim edildi (1Password / hardware token önerisi). Public key `app/update/manifest_pubkey.pem`'e gömüldü.
- **Cost estimator token avg 1500** — gerçek token tracking 016'da `tracker.bump(name, tokens_in, tokens_out)` parametre uzantısı ile.
- **Learnings hook integration** opsiyonel — `delegate_nudge.py` patch'i atlanabilir; manual API + MCP tool yeterli.
- **Watchdog deploy.sh test edilmiyor** — manuel infra script. CI'da shellcheck ile syntax kontrol opsiyonel.
- **Cache integration** orchestrator-level — bireysel provider çağrıları (basic_providers.ask_*) cache'ten geçmiyor. Mevcut tasarım: cascade ÜZERİNDE cache, doğrudan provider çağrıları cache'siz. Bu kabul edilebilir; LLM sonucu deterministik değil, tek-shot tool çağrısında cache değer az.
- **Panel placeholder kalan**: `_build_orchestrator.judge` (014'te placeholder kaldı, 016'da senior_judge entegrasyonu) + `symbol_graph` (016 task'ı ayrı).
- **Hook delegate_nudge learnings.log** — opsiyonel, atlanırsa MCP tool ile kullanıcı manuel ekler.

## Kapsam Dışı (016+'a)

- Symbol graph real implementation (AST parser, neighbors, search)
- RAG hybrid (BM25 + cosine)
- ML-based persona training (logistic regression)
- Real token tracking (tracker.bump tokens_in/out)
- Multi-channel release tracks (stable/beta/canary)
- Watchdog real scrape parsers (provider başına custom)
- Cost estimator gerçek token sayıları (1500 avg yerine)
- Encryption key rotation cron (vault rotate scheduled)
