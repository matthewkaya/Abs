# Task 013 — Encrypted Secrets Vault (sops + age)

**Tahmini süre:** 4-5 saat (9 modül + setup wizard refactor + Dockerfile + plaintext migration)
**Önkoşul:** 012 tamam (92 MCP tool, 178/178 pytest yeşil)

## Bağlam

011-012 boyunca müşteri **API key'leri plaintext `.env`** dosyasında saklanıyor — Setup wizard adım 4 (Anthropic) + adım 5 (opsiyonel provider'lar) `_persist_env_var` ile düz metin yazıyor. Bu **kritik güvenlik açığı**: müşteri Docker volume çalınırsa Anthropic + Stripe webhook secret + Groq + Gemini + Cerebras + Cohere + license key tamamen açığa çıkar.

013 bu debt'i kapatır: **Mozilla sops + age** ile encrypted at-rest secrets vault.

**Tasarım kararı (gptoss qual_analysis 2026-04-25):** sops + age kombinasyonu seçildi. Sebep:
- Restart sonrası unattended boot (master key host-side dosya volume mount → otomatik decrypt)
- Volume çalınsa bile master key ayrı tutulduğu sürece ciphertext işe yaramaz
- Rotation `sops -e -i secrets.yaml` tek komut → panel butonu
- 3MB binary footprint (alpine OK), build complexity yok
- Python Fernet alternatifi: ~30MB build + key plaintext env'de risk → reddedildi
- HashiCorp Vault: ayrı container + unseal mekanizması → MVP için overkill, reddedildi

**Tool sayısı hedefi:** 92 → **93 tool** (+1: `vault_status`).
**Test sayısı hedefi:** 178 → **~195+ test** (+17: 6 vault core, 3 rotation, 3 migration, 3 setup integration, 1 mcp, 1 dockerfile smoke).

## ⚠️ KRITIK KISITLAR

1. **Master key dosyası SECRETS.YAML İLE AYNI VOLUME'DA OLMAMALI.** Docker compose 2 ayrı volume:
   - `abs-data:/app/data` (encrypted `secrets.yaml` burada)
   - `abs-vault-key:/app/vault-key:ro` (master key buradadır, **ayrı volume**)
   - Müşteri docker-compose.yml'i bu yapı için patch edilecek (`infra/docker-compose.yml`)

2. **Subprocess çağrıları**: sops + age Python wrapper'ı YOK. `subprocess.run(["sops", "-d", path], capture_output=True, timeout=10)`. Python wrapper paketleri (pyage, sops-python) maintenance riski → kullanmıyoruz.

3. **Test ortamında sops/age binary olmayabilir.** Strateji: `pytest.importorskip` analoğu — test başında binary varlık kontrol, yoksa `pytest.skip("sops binary not installed")`. Critical path testler için **subprocess.run mock** (monkeypatch) kullan.

4. **Cleartext disk'te kalmasın.** `sops -d` stdout'a yazsın, dosyaya yazma (`-o /tmp/clear.yaml` YASAK). Memory'de dict cache.

5. **Mevcut 178 test bozulmasın.** Setup wizard testleri (`test_setup_wizard.py` 7 test) refactor edilecek — vault entegrasyonu sonrası API key sops'a yazılıyor olacak. Mock vault fixture autouse.

6. **`.env` plaintext migration**: Boot'ta `.env`'de `ABS_ANTHROPIC_API_KEY=sk-ant-...` görürse → sops'a yaz + `.env`'den sil. Audit log.

## Giriş (Mevcut Durum — Worker doğrulasın)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                        # 178 passed
which sops age 2>&1                                        # binary'ler kurulu mu?
# Yoksa: brew install sops age (macOS) | apt install sops age (Linux)
sops --version; age --version                              # versiyonlar bilgi
.venv/bin/python -c "from app.api.setup import _persist_env_var; print(_persist_env_var)"
# 012'de yazılmış helper, 013'te _persist_encrypted_secret'a refactor olacak
ls /Users/eneseserkan/Main/abs-server-product/infra/      # docker-compose.yml + Caddyfile + install.sh
```

**Mevcut altyapı (013 üzerine inşa edecek):**
- `app/api/setup.py::_persist_env_var` — plaintext .env writer (refactor)
- `app/config.py::Settings` — 6 API key alanı (anthropic, groq, gemini, cerebras, cohere, cf_*)
- `infra/docker-compose.yml` — `abs-data` volume tek (013'te `abs-vault-key` eklenecek)
- `core/backend/Dockerfile` — multi-stage builder/runtime (010'da patch edildi)

**Yeni dosyalar (013):**
- `app/vault/__init__.py` (re-export)
- `app/vault/runner.py` — sops/age subprocess wrapper
- `app/vault/cache.py` — memory cache + settings runtime override
- `app/vault/migration.py` — plaintext .env → sops migration
- `app/vault/audit.py` — JSONL audit log (rotate, decrypt, migration)
- `app/api/secrets.py` — rotation endpoint (admin auth)
- `app/mcp/tools/vault_tools.py` — vault_status MCP tool
- `infra/scripts/init_vault.sh` — `age-keygen` master key oluşturma (manuel ilk kurulum)
- 6 yeni test dosyası

**Patch'lenecek dosyalar:**
- `app/api/setup.py` — `_persist_env_var` → `_persist_encrypted_secret`, adım 4-5 sops'a yazsın
- `app/main.py` — lifespan'de vault decrypt + cache + migration kontrolü
- `app/mcp/server.py` — vault_tools register
- `infra/docker-compose.yml` — `abs-vault-key` volume ekle
- `core/backend/Dockerfile` — sops + age binary install (builder+runtime)
- `infra/install.sh` — kurulum script'inde `init_vault.sh` çağrısı
- `tests/conftest.py` — vault mock fixture autouse
- `tests/test_setup_wizard.py` — sops mock entegrasyonu
- `tests/test_tools_count.py` — 92 → 93 + `vault_status` must_have

## Beklenen Çıktı

### A. Vault Core — Runner + Cache

**Yeni dosya** `app/vault/runner.py` (~140 satır):

```python
"""sops + age subprocess wrapper.

CLI çağrıları:
  sops -d <path>                    → stdout: plaintext yaml
  sops -e -i <path>                 → in-place encrypt
  age-keygen -o <key_path>          → yeni master key

Master key dosya yolu: settings.vault_key_path (default /app/vault-key/age.key)
Secrets dosyası:       settings.vault_secrets_path (default /app/data/secrets.yaml)
"""
from __future__ import annotations
import json
import logging
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, Optional

import yaml  # pyyaml — pyproject.toml'da yok, eklenecek

from app.config import settings

logger = logging.getLogger(__name__)


class VaultError(Exception):
    """Vault işlem hatası — non-transient veya transient."""
    def __init__(self, msg: str, *, transient: bool = False):
        super().__init__(msg)
        self.transient = transient


def sops_available() -> bool:
    return shutil.which("sops") is not None and shutil.which("age") is not None


def master_key_exists() -> bool:
    return Path(settings.vault_key_path).is_file()


def _sops_env() -> Dict[str, str]:
    """Subprocess'a SOPS_AGE_KEY_FILE inject et."""
    env = os.environ.copy()
    env["SOPS_AGE_KEY_FILE"] = settings.vault_key_path
    return env


def decrypt_all() -> Dict[str, Any]:
    """secrets.yaml'ı decrypt et, dict döndür."""
    if not sops_available():
        raise VaultError("sops/age binary kurulu değil", transient=False)
    if not master_key_exists():
        raise VaultError(
            f"Master key bulunamadı: {settings.vault_key_path}",
            transient=False,
        )
    secrets_path = Path(settings.vault_secrets_path)
    if not secrets_path.is_file():
        return {}  # vault boş — fresh install
    try:
        result = subprocess.run(
            ["sops", "-d", str(secrets_path)],
            env=_sops_env(),
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        raise VaultError(f"sops decrypt fail: {exc.stderr[:200]}", transient=False) from exc
    except subprocess.TimeoutExpired as exc:
        raise VaultError("sops decrypt timeout", transient=True) from exc
    try:
        return yaml.safe_load(result.stdout) or {}
    except yaml.YAMLError as exc:
        raise VaultError(f"yaml parse fail: {exc}", transient=False) from exc


def encrypt_all(data: Dict[str, Any]) -> None:
    """Tüm dict'i encrypt et, secrets.yaml'a in-place yaz."""
    if not sops_available():
        raise VaultError("sops/age binary kurulu değil", transient=False)
    secrets_path = Path(settings.vault_secrets_path)
    secrets_path.parent.mkdir(parents=True, exist_ok=True)
    age_recipient = _read_age_recipient()
    # Önce plain yaml yaz, sonra in-place encrypt
    plain_yaml = yaml.safe_dump(data, allow_unicode=True, sort_keys=True)
    tmp_path = secrets_path.with_suffix(".yaml.tmp")
    tmp_path.write_text(plain_yaml, encoding="utf-8")
    try:
        subprocess.run(
            ["sops", "-e", "-i",
             "--age", age_recipient,
             "--unencrypted-suffix", "_unencrypted",
             str(tmp_path)],
            env=_sops_env(),
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )
        # Atomic move
        tmp_path.replace(secrets_path)
    except subprocess.CalledProcessError as exc:
        if tmp_path.exists():
            tmp_path.unlink()
        raise VaultError(f"sops encrypt fail: {exc.stderr[:200]}", transient=False) from exc
    except subprocess.TimeoutExpired as exc:
        if tmp_path.exists():
            tmp_path.unlink()
        raise VaultError("sops encrypt timeout", transient=True) from exc


def _read_age_recipient() -> str:
    """Master key dosyasından public recipient'ı çıkar (age-keygen formatı)."""
    p = Path(settings.vault_key_path)
    for line in p.read_text(encoding="utf-8").splitlines():
        if line.startswith("# public key:"):
            return line.split(":", 1)[1].strip()
    raise VaultError("Master key public recipient bulunamadı", transient=False)


def write_secret(key: str, value: str) -> None:
    """Tek bir secret'ı upsert (decrypt → update → encrypt)."""
    data = decrypt_all()
    data[key] = value
    encrypt_all(data)


def read_secret(key: str) -> Optional[str]:
    """Tek secret oku (boot sonrası cache.py kullanın)."""
    return decrypt_all().get(key)


def delete_secret(key: str) -> bool:
    data = decrypt_all()
    if key not in data:
        return False
    del data[key]
    encrypt_all(data)
    return True
```

**Yeni dosya** `app/vault/cache.py` (~80 satır):

```python
"""Memory cache — boot'ta decrypt edilen secrets'ları runtime'da settings'e bağlar."""
from __future__ import annotations
import logging
from typing import Any, Dict
from app.config import settings

logger = logging.getLogger(__name__)

_cache: Dict[str, Any] = {}

# Vault'taki key isimleri → settings attribute eşleşmesi
_KEY_MAP = {
    "anthropic_api_key": "anthropic_api_key",
    "groq_api_key": "groq_api_key",
    "cerebras_api_key": "cerebras_api_key",
    "gemini_api_key": "gemini_api_key",
    "cf_account_id": "cf_account_id",
    "cf_api_token": "cf_api_token",
    "cohere_api_key": "cohere_api_key",
    "openrouter_api_key": "openrouter_api_key",
    "stripe_secret_key": "stripe_secret_key",
    "stripe_webhook_secret": "stripe_webhook_secret",
    "license_key": "license_key",
}


def boot_load() -> int:
    """Lifespan'de çağrılır — vault'tan settings'e secrets aktar."""
    from app.vault.runner import decrypt_all, master_key_exists, sops_available, VaultError
    if not sops_available() or not master_key_exists():
        logger.info("vault disabled (binary or master key missing) — settings env-from-shell only")
        return 0
    try:
        data = decrypt_all()
    except VaultError as exc:
        logger.warning("vault boot decrypt failed: %s", exc)
        return 0
    loaded = 0
    for vault_key, settings_attr in _KEY_MAP.items():
        if vault_key in data and data[vault_key]:
            setattr(settings, settings_attr, str(data[vault_key]))
            _cache[vault_key] = data[vault_key]
            loaded += 1
    logger.info("vault loaded %d secrets into settings", loaded)
    return loaded


def invalidate() -> None:
    """Rotation sonrası cache temizle, settings'e yeniden yükle."""
    _cache.clear()
    boot_load()


def known_keys() -> list[str]:
    return list(_KEY_MAP.keys())


def is_loaded(key: str) -> bool:
    return key in _cache
```

**Patch** `app/main.py` lifespan:

```python
@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_db()
    # 013 — vault boot decrypt + plaintext migration
    from app.vault.cache import boot_load
    from app.vault.migration import migrate_plaintext_env_to_vault
    try:
        migrate_plaintext_env_to_vault()  # bir defalık (idempotent)
    except Exception as exc:
        logger.warning("vault migration skipped: %s", exc)
    boot_load()
    # 011 demo start (mevcut)
    if not settings.license_key:
        from app.licensing.demo import start_demo
        try:
            start_demo()
        except Exception:
            pass
    if os.environ.get("ABS_TEST_MODE") == "1":
        yield
        return
    async with mcp_server.session_manager.run():
        yield
```

**Patch** `app/config.py`:
```python
# 013 — vault paths
vault_key_path: str = "/app/vault-key/age.key"
vault_secrets_path: str = "/app/data/secrets.yaml"
```

**Patch** `pyproject.toml`:
```toml
"PyYAML>=6.0",
```

**Test** `tests/test_vault_runner.py` (~150 satır, 6 test):

1. `test_sops_available_false_when_binary_missing`: monkeypatch `shutil.which` → None → False.
2. `test_decrypt_all_returns_empty_when_secrets_yaml_missing`: tmp_path, no file → `{}`.
3. `test_encrypt_decrypt_roundtrip` (real binary, skip if missing): age-keygen + encrypt 3 anahtar + decrypt → eşit.
4. `test_decrypt_raises_when_master_key_missing`: vault_key_path olmayan dosya → `VaultError`.
5. `test_encrypt_subprocess_fail_raises_non_transient`: monkeypatch subprocess.run CalledProcessError → `VaultError(transient=False)`.
6. `test_write_secret_upserts`: encrypt empty + write_secret('foo', 'bar') + decrypt → `{'foo':'bar'}`.

### B. Setup Wizard Refactor — Plaintext Yerine sops

**Patch** `app/api/setup.py`:

`_persist_env_var(key, value)` → `_persist_encrypted_secret(key, value)`:

```python
def _persist_encrypted_secret(key: str, value: str) -> bool:
    """sops vault'a yaz; vault yoksa fallback olarak .env'e (yalnızca dev/test)."""
    from app.vault.runner import sops_available, master_key_exists, write_secret, VaultError
    if sops_available() and master_key_exists():
        try:
            write_secret(key, value)
            from app.vault.audit import log_event
            log_event("write", key, source="setup_wizard")
            return True
        except VaultError as exc:
            logger.warning("vault write fail, falling back to .env: %s", exc)
    # Fallback (dev / vault disabled): mevcut .env writer
    return _persist_env_var(f"ABS_{key.upper()}", value)
```

Step 4 (anthropic) ve Step 5 (providers) handler'larında çağrı `_persist_env_var` → `_persist_encrypted_secret`.

**Patch** `tests/test_setup_wizard.py`:
- Autouse fixture: `monkeypatch app.vault.runner.write_secret` → fake dict store
- 7 mevcut test write_secret çağrılarını assert etsin

### C. Plaintext Migration

**Yeni dosya** `app/vault/migration.py` (~80 satır):

```python
"""Boot'ta plaintext .env'den secrets'ları sops'a göç et + sil."""
from __future__ import annotations
import logging
import os
import re
from pathlib import Path
from app.config import settings

logger = logging.getLogger(__name__)

_PLAIN_ENV_KEYS = (
    "ABS_ANTHROPIC_API_KEY", "ABS_GROQ_API_KEY", "ABS_CEREBRAS_API_KEY",
    "ABS_GEMINI_API_KEY", "ABS_CF_ACCOUNT_ID", "ABS_CF_API_TOKEN",
    "ABS_COHERE_API_KEY", "ABS_OPENROUTER_API_KEY",
    "ABS_STRIPE_SECRET_KEY", "ABS_STRIPE_WEBHOOK_SECRET",
)


def migrate_plaintext_env_to_vault() -> int:
    """Idempotent — sadece sops/master key varsa, .env'de plaintext key görürse migrate."""
    from app.vault.runner import sops_available, master_key_exists, decrypt_all, write_secret
    from app.vault.audit import log_event
    if not sops_available() or not master_key_exists():
        return 0
    env_path = Path(".env")
    if not env_path.is_file():
        return 0
    lines = env_path.read_text(encoding="utf-8").splitlines()
    existing_vault = decrypt_all()
    migrated_count = 0
    new_lines = []
    for line in lines:
        m = re.match(r"^(ABS_[A-Z_]+)=(.+)$", line)
        if not m:
            new_lines.append(line)
            continue
        env_key, env_val = m.group(1), m.group(2)
        if env_key not in _PLAIN_ENV_KEYS or not env_val:
            new_lines.append(line)
            continue
        vault_key = env_key[4:].lower()  # ABS_GROQ_API_KEY → groq_api_key
        if vault_key in existing_vault:
            # Vault zaten var, .env'den sil
            log_event("migration_skip_already_in_vault", vault_key)
            migrated_count += 1
            continue  # bu satırı atla — .env'den çıkar
        try:
            write_secret(vault_key, env_val.strip('"').strip("'"))
            log_event("migration", vault_key, source="env_plaintext")
            migrated_count += 1
            # .env'den çıkar (line skip edildi)
        except Exception as exc:
            logger.warning("migration fail %s: %s", env_key, exc)
            new_lines.append(line)  # başarısızsa koru
    if migrated_count > 0:
        env_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
        log_event("migration_complete", "_aggregate", source="env_plaintext", count=migrated_count)
    return migrated_count
```

**Test** `tests/test_vault_migration.py` (~120 satır, 3 test):

1. `test_migration_skipped_when_no_vault`: `.env` plaintext var ama master key yok → 0 migrated, `.env` değişmedi.
2. `test_migration_moves_plaintext_to_vault`: `.env` `ABS_ANTHROPIC_API_KEY=sk-ant-test` + master key + sops mock → vault'a yazılır, `.env`'den silinir, audit log yazılır.
3. `test_migration_idempotent`: 2 kere çağır → 2. çağrıda 0 migrated.

### D. Audit Log

**Yeni dosya** `app/vault/audit.py` (~50 satır):

```python
"""Vault audit log — JSONL append-only."""
from __future__ import annotations
import json
import time
from pathlib import Path
from typing import Any
from app.config import settings


def _audit_path() -> Path:
    p = Path(settings.data_dir) / "vault_audit.jsonl"
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def log_event(event: str, key: str, **extra: Any) -> None:
    """Vault olayını audit log'a ekle. Cleartext value YAZMA."""
    entry = {"ts": time.time(), "event": event, "key": key, **extra}
    try:
        with open(_audit_path(), "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass


def read_recent(limit: int = 50) -> list[dict]:
    p = _audit_path()
    if not p.is_file():
        return []
    try:
        return [json.loads(line) for line in p.read_text(encoding="utf-8").splitlines()[-limit:]]
    except Exception:
        return []
```

### E. Rotation Endpoint + Panel Integration

**Yeni dosya** `app/api/secrets.py` (~80 satır):

```python
"""Vault rotation API — panel'den admin auth ile."""
from __future__ import annotations
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from app.api.auth import current_admin
from app.vault.audit import log_event
from app.vault.cache import known_keys, invalidate
from app.vault.runner import write_secret, VaultError, sops_available, master_key_exists

router = APIRouter(prefix="/v1/secrets", tags=["secrets"])


class RotateRequest(BaseModel):
    key: str = Field(..., min_length=3)
    new_value: str = Field(..., min_length=1)


@router.post("/rotate")
async def rotate_secret(body: RotateRequest, _admin: dict = Depends(current_admin)) -> dict:
    if not sops_available() or not master_key_exists():
        raise HTTPException(status_code=503, detail="Vault yapılandırılmadı")
    if body.key not in known_keys():
        raise HTTPException(status_code=400, detail=f"Bilinmeyen key: {body.key}")
    try:
        write_secret(body.key, body.new_value)
    except VaultError as exc:
        raise HTTPException(status_code=500, detail=f"Vault yazma hatası: {exc}")
    log_event("rotate", body.key, source="panel_api")
    invalidate()
    return {"status": "ok", "key": body.key, "rotated_at": __import__("time").time()}


@router.get("/status")
async def secrets_status(_admin: dict = Depends(current_admin)) -> dict:
    """Cleartext yok — sadece configured/not-configured listesi."""
    from app.vault.cache import is_loaded
    keys = known_keys()
    return {
        "vault_enabled": sops_available() and master_key_exists(),
        "keys": [{"name": k, "configured": is_loaded(k)} for k in keys],
    }
```

**Patch** `app/main.py`:
```python
from app.api import secrets as secrets_router
app.include_router(secrets_router.router)
```

**Test** `tests/test_secrets_api.py` (~110 satır, 3 test):

1. `test_rotate_unknown_key_400`: POST `/v1/secrets/rotate` `{key:"foo", new_value:"x"}` → 400.
2. `test_rotate_writes_and_invalidates_cache`: monkeypatch `write_secret` + `invalidate` → çağrılır.
3. `test_status_returns_configured_keys_no_cleartext`: response `{vault_enabled, keys:[{name, configured}]}`, **value YOK**.

### F. MCP Tool — vault_status

**Yeni dosya** `app/mcp/tools/vault_tools.py` (~40 satır):

```python
"""Vault durum sorgulama MCP tool (013)."""
from __future__ import annotations
import json
from typing import List
from app.mcp.middleware import with_hooks
from app.mcp.server import mcp_server
from app.mcp.tracking import tracker

REGISTERED_TOOLS: List[str] = []


@mcp_server.tool()
@with_hooks("vault_status")
async def vault_status() -> str:
    """Vault snapshot — configured key listesi + audit son 5 olay. Cleartext YOK."""
    await tracker.bump("vault_status")
    from app.vault.runner import sops_available, master_key_exists
    from app.vault.cache import known_keys, is_loaded
    from app.vault.audit import read_recent
    payload = {
        "vault_enabled": sops_available() and master_key_exists(),
        "binary_sops": __import__("shutil").which("sops") is not None,
        "binary_age": __import__("shutil").which("age") is not None,
        "keys": [{"name": k, "configured": is_loaded(k)} for k in known_keys()],
        "recent_audit": read_recent(limit=5),
    }
    return json.dumps(payload, ensure_ascii=False, indent=2)


REGISTERED_TOOLS.extend(["vault_status"])
```

**Patch** `app/mcp/server.py::register_all_tools` — `from app.mcp.tools import vault_tools` import + count.

**Patch** `tests/test_tools_count.py`: 92 → **93**, must_have'a `"vault_status"`.

### G. Dockerfile + docker-compose Patch

**Patch** `core/backend/Dockerfile`:

```dockerfile
FROM base AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ libsqlite3-dev patch curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# 013 — sops + age (multi-arch)
ARG SOPS_VERSION=3.9.4
ARG AGE_VERSION=1.2.1
RUN curl -fsSL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" -o /usr/local/bin/sops && \
    chmod +x /usr/local/bin/sops && \
    curl -fsSL "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz" | tar -xzC /tmp && \
    mv /tmp/age/age /tmp/age/age-keygen /usr/local/bin/ && \
    rm -rf /tmp/age
COPY pyproject.toml ./
COPY app/ ./app/
RUN pip install --prefix=/install .

FROM base AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends patch ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/local/bin/sops /usr/local/bin/sops
COPY --from=builder /usr/local/bin/age /usr/local/bin/age
COPY --from=builder /usr/local/bin/age-keygen /usr/local/bin/age-keygen
COPY --from=builder /install /usr/local
COPY app/ ./app/
RUN mkdir -p /app/data /app/vault-key && \
    useradd --create-home --uid 1000 abs && \
    chown -R abs:abs /app
USER abs
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)" || exit 1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Patch** `infra/docker-compose.yml`:

```yaml
services:
  backend:
    build: ../core/backend
    env_file: .env
    expose:
      - "8000"
    volumes:
      - abs-data:/app/data
      - abs-vault-key:/app/vault-key:ro    # 013 — master key ayrı volume, read-only
    restart: unless-stopped

  caddy:
    # mevcut
    
volumes:
  abs-data:
  abs-vault-key:           # 013
  caddy-data:
  caddy-config:
```

**Yeni dosya** `infra/scripts/init_vault.sh` (~40 satır):

```bash
#!/usr/bin/env bash
# ABS Vault initialization — age master key oluştur (TEK SEFER, kurulumda).
# Kullanım: ./init_vault.sh
# Sonuç: docker volume `abs-vault-key`'in içine `age.key` yazılır.

set -euo pipefail

VOLUME_NAME="${VOLUME_NAME:-abs-server-product_abs-vault-key}"

if ! command -v docker >/dev/null 2>&1; then
    echo "ERR: docker bulunamadı" >&2
    exit 1
fi

# Volume zaten var mı?
if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    docker volume create "$VOLUME_NAME"
fi

# Geçici container ile içine girip age-keygen çalıştır
docker run --rm \
    -v "$VOLUME_NAME:/vault-key" \
    --entrypoint sh \
    automatia-abs:latest \
    -c '
if [ -f /vault-key/age.key ]; then
    echo "Master key zaten var: /vault-key/age.key (atlandı)"
    exit 0
fi
age-keygen -o /vault-key/age.key
chmod 600 /vault-key/age.key
echo "Master key oluşturuldu: /vault-key/age.key"
echo "Public recipient:"
grep "# public key:" /vault-key/age.key || true
'

echo "✓ Vault initialized. Backend'i şimdi başlatabilirsiniz: docker compose up -d backend"
```

**Patch** `infra/install.sh` — eğer mevcutsa `init_vault.sh` çağrısı (yoksa not olarak install.sh'a ekle).

**Test** `tests/test_dockerfile_smoke.py` (~30 satır, 1 test):
- `test_dockerfile_contains_sops_age_install`: Dockerfile dosyası `/usr/local/bin/sops` ve `age-keygen` referanslarını içerir.

### H. Tests Toplu

**`tests/conftest.py` patch** — autouse vault mock fixture:

```python
@pytest.fixture(autouse=True)
def _mock_vault(monkeypatch, tmp_path):
    """Tüm testlerde vault subprocess'leri mock — gerçek sops çağrısı yapma."""
    from app.config import settings
    monkeypatch.setattr(settings, "vault_key_path", str(tmp_path / "age.key"))
    monkeypatch.setattr(settings, "vault_secrets_path", str(tmp_path / "secrets.yaml"))
    # Default: vault disabled (sops_available=False) — testler explicit enable etsin
    monkeypatch.setattr("app.vault.runner.sops_available", lambda: False)
    monkeypatch.setattr("app.vault.runner.master_key_exists", lambda: False)
```

İndividual test dosyaları gerektiğinde monkeypatch override ile sops'u "available" yapsın + write_secret/decrypt_all mock store ile çalışsın.

## Adımlar (Worker Claude için)

### 1. Önkoşul (5 dk)
```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pytest -q                                      # 178 passed
which sops age 2>&1                                      # binary'ler varsa real test, yoksa skip
.venv/bin/pip install pyyaml                             # geçici, sonra pyproject'e eklenecek
```

### 2. Modul A — Vault Core (60 dk)
1. `app/vault/__init__.py` (re-export)
2. `app/vault/runner.py` (sops/age subprocess wrapper)
3. `app/vault/cache.py` (memory cache + settings override)
4. `app/config.py` patch — vault_key_path + vault_secrets_path
5. `pyproject.toml` patch — `pyyaml>=6.0`
6. `tests/test_vault_runner.py` (6 test, 3'ü real sops gerektir, importorskip)
7. `pytest tests/test_vault_runner.py -v` → 6 PASS (real binary varsa) veya 3 SKIP + 3 PASS

### 3. Modul B — Audit Log (15 dk)
1. `app/vault/audit.py` (JSONL append + read_recent)
2. `tests/test_vault_audit.py` (~50 satır, 2 test: log + read)
3. `pytest tests/test_vault_audit.py -v` → 2 PASS

### 4. Modul C — Migration (30 dk)
1. `app/vault/migration.py` (.env plaintext → sops)
2. `tests/test_vault_migration.py` (3 test, monkeypatch sops + tmp_path .env)
3. `pytest tests/test_vault_migration.py -v` → 3 PASS

### 5. Modul D — Setup Wizard Refactor (30 dk)
1. `app/api/setup.py` patch — `_persist_env_var` → `_persist_encrypted_secret` (fallback'lı)
2. `tests/conftest.py` patch — autouse vault mock fixture
3. `tests/test_setup_wizard.py` patch — write_secret çağrı assertion
4. `pytest tests/test_setup_wizard.py -v` → 7 PASS (mevcut)

### 6. Modul E — Rotation API (30 dk)
1. `app/api/secrets.py` (rotate + status endpoint)
2. `app/main.py` patch — secrets_router register
3. `tests/test_secrets_api.py` (3 test, admin auth mock)
4. `pytest tests/test_secrets_api.py -v` → 3 PASS

### 7. Modul F — MCP Tool (15 dk)
1. `app/mcp/tools/vault_tools.py` (1 tool)
2. `app/mcp/server.py` Read → tam Write override (vault_tools import)
3. `tests/test_tools_count.py` patch (92 → 93, vault_status must_have)
4. `pytest tests/test_tools_count.py -v` → 2 PASS

### 8. Modul G — Lifespan Integration (20 dk)
1. `app/main.py` patch — lifespan'de `migrate_plaintext_env_to_vault()` + `boot_load()`
2. Run uvicorn local → log "vault loaded N secrets" görünüyor mu kontrol
3. Mevcut testler hâlâ yeşil mi kontrol (test mode lifespan skip ettiği için OK olmalı)

### 9. Modul H — Dockerfile + docker-compose + init_vault.sh (25 dk)
1. `core/backend/Dockerfile` Write tam override (sops + age install)
2. `infra/docker-compose.yml` Write tam override (`abs-vault-key` volume)
3. `infra/scripts/init_vault.sh` (yeni dosya, executable)
4. `infra/install.sh` patch — `init_vault.sh` çağrı dökümante (yorum olarak)
5. `tests/test_dockerfile_smoke.py` (1 test)
6. `pytest tests/test_dockerfile_smoke.py -v` → 1 PASS
7. (Opsiyonel) `docker compose -f infra/docker-compose.yml build backend` smoke

### 10. Tam Test Suite (5 dk)
```bash
.venv/bin/pytest -q
# 195+ passed (real binary varsa) veya ~189 + 6 SKIP
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 93
```

### 11. Live MCP Smoke (15 dk)

Eğer sops + age yerelde kuruluysa:
```bash
mkdir -p /tmp/abs-013-smoke/{vault-key,data}
age-keygen -o /tmp/abs-013-smoke/vault-key/age.key
ABS_VAULT_KEY_PATH=/tmp/abs-013-smoke/vault-key/age.key \
ABS_VAULT_SECRETS_PATH=/tmp/abs-013-smoke/data/secrets.yaml \
ABS_DATA_DIR=/tmp/abs-013-smoke/data \
.venv/bin/uvicorn app.main:app --port 8765 &

# 4 kanıt:
# 01: vault_status MCP → vault_enabled:true, binary'ler true, keys hepsi configured:false (yeni vault)
# 02: POST /v1/secrets/rotate {key:"groq_api_key", new_value:"test123"} (admin auth) → 200
# 03: vault_status sonrası → keys[groq].configured=true
# 04: cat /tmp/abs-013-smoke/data/secrets.yaml → ENC[AES256_GCM,...] (cleartext YOK)
```

Yoksa: kanıt dosyalarına "sops binary not present in CI environment, skipped live smoke" notu yaz.

### 12. Tamamlama
1. `_agent-tasks/completed/013-encrypted-secrets-vault.md` taşı
2. `013-encrypted-secrets-vault-summary.md` yaz:
   - 9 modül + dosya listesi
   - Test sonuçları (178 → 195+ veya skip count)
   - Smoke kanıtı (real binary varsa) veya neden skip
   - Notlar Planlayıcıya

## Doğrulama (Worker fail-fast)

```bash
cd /Users/eneseserkan/Main/abs-server-product/core/backend
.venv/bin/pip install pyyaml
.venv/bin/pytest -q                                                # 195+ passed (binary) veya 189+SKIP
.venv/bin/pytest tests/test_tools_count.py -v                      # 93 guard
.venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
# 93
.venv/bin/python -c "from app.vault.runner import sops_available; print('sops:', sops_available())"
.venv/bin/python -c "from app.vault.cache import known_keys; print(len(known_keys()), 'keys mapped')"
# 11 keys mapped
docker compose -f infra/docker-compose.yml config | grep -A2 vault-key  # volume tanımı görünür mü
```

## Notlar Planlayıcıya (Worker doldursun)

- **Master key dosyası volume disipliniyle ayrı tutuluyor** — `abs-vault-key` volume `:ro` (read-only) backend container'ına mount. Müşteri host'ta volume'u doğrudan disk'e backup etmemeli; ayrı backup stratejisi (offsite, encrypted) gerekli. Operations doc'a not eklenmeli (014+).
- **Master key kayıp = veri kaybı.** Yedek şifrelenmiş key'in kopyası müşteri tarafında zorunlu. Setup wizard'a "Master key recovery" UI 014'te düşünülebilir (Shamir secret sharing veya manuel paper backup).
- **Rotation panel UI** (`/panel/secrets`) bu task'ta YOK — sadece API endpoint. UI 014/015'e bırakıldı.
- **age-keygen CI/CD test'te yok** olabilir — bu yüzden critical-path testler subprocess mock kullanıyor. Real roundtrip testleri pytest.skip ile bypass edilir.
- **Stripe webhook secret de vault'ta** — webhook handler'da `settings.stripe_webhook_secret` boot_load sonrası gelmiş olur. Mevcut 4 stripe webhook testi mock kullandığı için etkilenmez.
- **`ABS_*` env var'ları .env'de hâlâ tutulabilir** (örn. `ABS_DATABASE_URL`, `ABS_DOMAIN`, `ABS_DATA_DIR`) — sadece API key'ler ve license key vault'a girer. Migration sadece `_PLAIN_ENV_KEYS` listesindekileri taşır.
- **Subprocess timeout 10s** — büyük secrets dosyası için yeterli; 100+ key olursa artırılabilir.

## Kapsam Dışı (014+'a)

- Master key recovery UI (Shamir secret sharing veya paper backup)
- Vault rotation panel UI (HTML form)
- Update Channel + Watchdog (014)
- Multi-key per provider (key versioning)
- Secrets backup encryption (offsite)
- Vault unseal mekanizması (HashiCorp tarzı)
- Audit log retention policy (cleanup_old)
- Encrypted log persistence
