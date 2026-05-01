# Task 001 — Scaffold: Docker Compose + Klasör + Caddy

## Bağlam

ABS ürün klasörü (`abs-server-product/`) ve `docs/` içi hazır. Artık **kod iskeleti** kurulacak. Bu task, MVP'nin Docker Compose ile çalışabilen boş iskeletini oluşturur. Henüz iş mantığı YOK — sadece yapı.

Bağlı karar dokümanları:
- `docs/design-decisions.md` — 24 karar
- `docs/architecture.md` — bileşen + endpoint
- `docs/operations.md` — update channel + watchdog
- `docs/research/*.md` — arka plan

## Giriş (Mevcut Durum)

`abs-server-product/` klasörü şu hâlde:
```
abs-server-product/
├── docs/            (dolu — karar + research)
├── _agent-tasks/    (bu klasör)
├── core/            (BOŞ)
├── infra/           (BOŞ)
├── marketing/       (BOŞ)
└── business/        (BOŞ)
```

## Beklenen Çıktı

### core/
- [ ] `core/backend/pyproject.toml` — Python proje (FastAPI + uvicorn + sqlmodel + sops-decrypt)
- [ ] `core/backend/app/__init__.py` — boş paket
- [ ] `core/backend/app/main.py` — FastAPI instance + health endpoint + placeholder routes
- [ ] `core/backend/app/config.py` — env-var config loader (pydantic-settings)
- [ ] `core/backend/Dockerfile` — python:3.11-slim base, multi-stage
- [ ] `core/backend/tests/test_smoke.py` — health endpoint test (pytest)

### infra/
- [ ] `infra/docker-compose.yml` — services: `backend` + `caddy` + opsiyonel `ollama`
- [ ] `infra/Caddyfile` — 2 site: port 80 → redirect 443, `abs.local:443` → reverse_proxy backend:8000
- [ ] `infra/.env.example` — ABS_ADMIN_EMAIL, ABS_DOMAIN, ABS_SSL_MODE, ABS_LICENSE_KEY placeholder'ları
- [ ] `infra/install.sh` — Docker + Compose kontrolü, `.env` oluşturma, `docker compose up -d`

### Root
- [ ] `abs-server-product/README.md` — kısa ürün README (docs'a linkler)
- [ ] `abs-server-product/.gitignore` — `.env`, `*.sqlite`, `__pycache__/`, secrets/

## Kısıtlar

- ❌ SERVER klasörüne dokunma (`/Automatia BCN/SERVER/`)
- ❌ İş mantığı kod yazma (75 MCP tool vb.) — sadece **iskelet**
- ❌ `core/panel/`, `core/admin/` henüz dokunma — sonraki task'larda
- ✅ Python 3.11+, FastAPI latest, SQLModel, Pydantic v2
- ✅ Caddy v2 (otomatik HTTPS opsiyonu Caddyfile'da)
- ✅ Docker Compose v2 syntax
- ✅ pytest test eklenecek (minimal smoke: `/healthz` endpoint 200 döner)

## Adımlar

1. `core/backend/` altına Python FastAPI proje iskeleti kur
2. `app/main.py` içinde:
   ```python
   from fastapi import FastAPI
   app = FastAPI(title="Automatia ABS", version="0.1.0")

   @app.get("/healthz")
   def healthz():
       return {"status": "ok", "service": "abs-backend"}
   ```
3. `app/config.py`:
   ```python
   from pydantic_settings import BaseSettings
   class Settings(BaseSettings):
       admin_email: str = ""
       domain: str = "abs.local"
       ssl_mode: str = "internal"  # "internal" | "acme"
       license_key: str = ""
       class Config:
           env_prefix = "ABS_"
           env_file = ".env"
   settings = Settings()
   ```
4. `Dockerfile` (multi-stage):
   ```dockerfile
   FROM python:3.11-slim AS base
   WORKDIR /app
   COPY pyproject.toml .
   RUN pip install --no-cache-dir .
   COPY app/ ./app/
   EXPOSE 8000
   CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
   ```
5. `infra/docker-compose.yml`:
   ```yaml
   services:
     backend:
       build: ../core/backend
       env_file: .env
       expose: ["8000"]
       volumes:
         - abs-data:/app/data
     caddy:
       image: caddy:2
       ports: ["80:80", "443:443"]
       volumes:
         - ./Caddyfile:/etc/caddy/Caddyfile:ro
         - caddy-data:/data
         - caddy-config:/config
   volumes:
     abs-data:
     caddy-data:
     caddy-config:
   ```
6. `Caddyfile`:
   ```
   {
     auto_https off  # dev için; prod'da ssl_mode=acme yapıp kaldır
   }
   :80 {
     redir https://{host}{uri}
   }
   abs.local:443 {
     tls internal
     reverse_proxy backend:8000
   }
   ```
7. `install.sh`:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   command -v docker >/dev/null || { echo "Docker gerekli"; exit 1; }
   docker compose version >/dev/null || { echo "Docker Compose v2 gerekli"; exit 1; }
   [ -f .env ] || cp .env.example .env
   docker compose up -d --build
   echo "ABS kuruldu. Panel: https://abs.local"
   ```
8. `tests/test_smoke.py`:
   ```python
   from fastapi.testclient import TestClient
   from app.main import app

   def test_healthz():
       r = TestClient(app).get("/healthz")
       assert r.status_code == 200
       assert r.json()["status"] == "ok"
   ```
9. `pyproject.toml`:
   ```toml
   [project]
   name = "abs-backend"
   version = "0.1.0"
   requires-python = ">=3.11"
   dependencies = [
       "fastapi>=0.115",
       "uvicorn[standard]>=0.30",
       "pydantic>=2.8",
       "pydantic-settings>=2.4",
       "sqlmodel>=0.0.22",
   ]
   [project.optional-dependencies]
   dev = ["pytest>=8", "httpx>=0.27"]
   ```

## Doğrulama

```bash
# 1. Backend testi local
cd core/backend
pip install -e ".[dev]"
pytest tests/ -q
# Beklenen: 1 passed

# 2. Docker build
cd ../../infra
cp .env.example .env
docker compose build
# Beklenen: error yok

# 3. Docker up
docker compose up -d
sleep 5

# 4. Health check
curl -k https://abs.local/healthz  # (self-signed internal TLS)
# Beklenen: {"status":"ok","service":"abs-backend"}

# 5. Teardown
docker compose down
```

## Tamamlama

Bitirince:
1. `_agent-tasks/completed/001-scaffold-summary.md` yaz:
   - Ne eklendi (dosya listesi)
   - Test sonuçları (pytest + curl)
   - Blocker varsa not düş
2. Bu dosyayı `_agent-tasks/completed/` altına taşı.
3. Planlayıcı Claude'a rapor verilecek.

---

**Tahmini süre:** 45-90 dk (ilk proje scaffold her zaman biraz vakit alır)
**Sonraki task:** `002-licensing.md` — Stripe webhook + JWT lisans key üretici
