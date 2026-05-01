# Task 001 — Scaffold — Completion Summary

**Tarih:** 2026-04-23
**Durum:** ✅ Tamamlandı — tüm doğrulama geçti

## Eklenen Dosyalar

### core/backend/
- `pyproject.toml` — FastAPI + uvicorn + pydantic v2 + pydantic-settings + sqlmodel; dev: pytest + httpx
- `app/__init__.py` — boş paket
- `app/main.py` — FastAPI instance, `/healthz`, placeholder `/v1/license/status` + `/v1/update/channel`
- `app/config.py` — pydantic-settings v2 (`SettingsConfigDict`, `ABS_` prefix, `.env` yükleyici)
- `Dockerfile` — multi-stage (builder → runtime), non-root `abs` user (uid 1000), HEALTHCHECK, uvicorn entrypoint
- `tests/__init__.py` + `tests/test_smoke.py` — `/healthz` 200 + payload doğrulaması

### infra/
- `docker-compose.yml` — `backend` (build ../core/backend) + `caddy:2`; volumes: `abs-data`, `caddy-data`, `caddy-config`; restart: unless-stopped
- `Caddyfile` — `:80` → https redirect, `abs.local:443` → `tls internal` + `reverse_proxy backend:8000`, `auto_https off` (dev)
- `.env.example` — `ABS_ADMIN_EMAIL`, `ABS_DOMAIN`, `ABS_SSL_MODE=internal`, `ABS_LICENSE_KEY`
- `install.sh` — Docker + Compose v2 guard, `.env` kopyalama, `compose up -d --build` (executable)

### Root
- `README.md` — hızlı başlangıç + yapı + docs linkleri
- `.gitignore` — `.env`, `__pycache__`, `.venv`, `*.sqlite`, `secrets/`, caddy volume dizinleri

## Doğrulama Sonuçları

| Adım | Komut | Sonuç |
|------|-------|-------|
| pip install -e ".[dev]" | `python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"` | ✅ başarılı |
| pytest smoke | `.venv/bin/pytest tests/ -q` | ✅ `1 passed in 0.28s` |
| compose config | `docker compose config --quiet` | ✅ syntax geçerli |
| compose build | `docker compose build` | ✅ backend image build, caddy:2 pulled |
| compose up | `docker compose up -d` | ✅ backend + caddy up |
| backend healthz (internal) | `exec backend GET /healthz` | ✅ `200 {"status":"ok","service":"abs-backend"}` |
| Caddy HTTPS | `curl -sk --resolve abs.local:443:127.0.0.1 https://abs.local/healthz` | ✅ `200 {"status":"ok",...}` |
| HTTP→HTTPS redirect | `curl --resolve abs.local:80:127.0.0.1 http://abs.local/healthz` | ✅ `308 → https://abs.local/healthz` |
| Docker HEALTHCHECK | `docker inspect …State.Health.Status` | ✅ `healthy` |
| Teardown | `docker compose down` | ✅ temiz çıkış |

## Doğrulama Sırasında Yapılan Düzeltme

**Caddyfile — `auto_https off` kaldırıldı.** İlk versiyonda `auto_https off` ile `tls internal` birlikte kullanılıyordu; Caddy `auto_https off` iken internal CA'yı da devre dışı bıraktığı için TLS handshake'te `tlsv1 alert internal error (80)` atıyordu (cert üretilmiyor). Düzeltme:

- `auto_https off` bloğu kaldırıldı.
- Açık port `:443` belirtimi kaldırıldı (`abs.local:443` → `abs.local`). Caddy, public olmayan `abs.local` için otomatik olarak `tls internal`'a düşer, `:80`'den `:443`'e redirect'i kendisi yapar. Prod'da `abs.local`'i public domain ile değiştirince ACME kendiliğinden devreye girer.
- `:80 redir` manuel bloğu gereksiz oldu — Caddy'nin auto HTTPS redirect'i 308 döndürüyor.

## Notlar

- IDE (Pyright) `from app.config import ...` / `from app.main import ...` için "import could not be resolved" diagnostic üretti — editable install (`pip install -e`) sonrası runtime'da çözülür; CI / Docker etkilenmez.
- `config.py`'de pydantic v2 `SettingsConfigDict` kullanıldı (task şablonundaki `class Config` pydantic v1 stili idi — v2 gereği güncellendi).
- `main.py`'e 2 placeholder endpoint eklendi (`/v1/license/status`, `/v1/update/channel`) — sonraki task'ları ön-kablolamak için, iş mantığı içermezler.
- `docker-compose.yml`'de opsiyonel `ollama` servisi eklenmedi (task: "opsiyonel"); 002+ görevleri ihtiyacı netleştirdiğinde eklenir.
- `/etc/hosts`'ta `abs.local` yok — test için `curl --resolve abs.local:443:127.0.0.1` kullanıldı. Son kullanıcı için `install.sh` bir sonraki iterasyonda `/etc/hosts` uyarısı ekleyebilir.

## Sonraki Task

`002-licensing.md` — Stripe webhook + JWT lisans key üretici.
