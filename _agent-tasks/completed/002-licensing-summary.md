# Task 002 — Licensing — Completion Summary

**Tarih:** 2026-04-23
**Durum:** ✅ Tamamlandı — 12 pytest yeşil, Docker canlı webhook curl 400 doğru davranış

## Ne Yapıldı

### Yeni modüller (core/backend/app/)

| Dosya | Satır | İçerik |
|-------|------:|--------|
| `licensing/__init__.py` | 5 | re-export |
| `licensing/schemas.py` | 29 | `LicensePayload` (Pydantic v2, Literal tier) |
| `licensing/keys.py` | 48 | RSA 2048 keypair gen + PEM load (0o600 private) |
| `licensing/generator.py` | 51 | `generate_license()` — RS256 JWT |
| `licensing/verifier.py` | 52 | `verify_license()` — HTTPException TR mesajları |
| `api/__init__.py` | 0 | paket |
| `api/license.py` | 105 | POST `/v1/license/activate`, GET `/v1/license/status`, `.env` persist (atomik) |
| `api/webhooks/__init__.py` | 0 | paket |
| `api/webhooks/stripe.py` | 121 | POST `/webhooks/stripe` — imza doğrula → lisans üret → DB → email |
| `db/__init__.py` | 0 | paket |
| `db/models.py` | 25 | `License` SQLModel (jti unique, revoked alanları) |
| `db/session.py` | 49 | lazy engine + `init_db()` + `get_session()` dep |
| `email/__init__.py` | 0 | paket |
| `email/sender.py` | 71 | Jinja2 render + SMTP veya console fallback |
| `email/templates/license_delivery.html` | 42 | TR email template (inline CSS, subject comment) |

### Güncellenen

| Dosya | Değişiklik |
|-------|-----------|
| `pyproject.toml` | `stripe>=10`, `PyJWT[crypto]>=2.9`, `cryptography>=43`, `jinja2>=3.1`; dev: `respx>=0.21` |
| `app/config.py` | +10 env: stripe, private/public key path, smtp, database_url, env |
| `app/main.py` | router include (license + webhooks) + lifespan `init_db()` |
| `infra/.env.example` | Tüm yeni ABS_ env placeholder'ları |

### Testler (core/backend/tests/)

| Dosya | Test sayısı | Kapsam |
|-------|:-----------:|--------|
| `conftest.py` | — | session-scoped fixture: tmp RSA keys + SQLite + env + settings mutate |
| `test_licensing.py` | 4 | roundtrip / expired / tampered / malformed |
| `test_stripe_webhook.py` | 4 | missing sig / invalid sig / `checkout.session.completed` → DB kaydı + JWT / bilinmeyen event → ignored |
| `test_license_api.py` | 3 | unconfigured / activate→active roundtrip / invalid token |
| `test_smoke.py` (mevcut) | 1 | healthz |
| **Toplam** | **12** | |

**Toplam yeni/değişen satır:** ~905 satır (kod + test + template)

## Delegation Kullanımı

| MCP Tool | Çağrı | Başarılı/Kullanılan | Amaç |
|----------|:----:|:--------------------:|------|
| `mcp__abs__rag_query` | 2 | 1 | Stripe webhook FastAPI pattern research (diğeri TPM limit) |
| `mcp__abs__qual_code` | 2 | 2 | Licensing modülü (5 dosya, ~185 satır) + activation endpoint (~105 satır) |
| `mcp__abs__qual_tr` | 1 | 1 | Email HTML template (Türkçe) |
| `mcp__abs__fullstack` (be,quality) | 1 | 0 | Stripe webhook — prompt TPM limiti aştı, `ask_gptoss`'a fallback |
| `mcp__abs__ask_gptoss` | 1 | 1 | Stripe webhook endpoint (~121 satır) |
| `mcp__abs__write_tests` | 1 | 0 | CodeLlama çıktısı FastAPI TestClient semantikleri yanlış (`app.test_client()` yok), testleri lokal yazdım |
| `mcp__abs__judge_patch` | 1 | 1 | `generator.py` skoru: combined 6.07 (LLM 8.0 / AST 4.78 — AST düşük çünkü docstring+type_hint oranları Enes fingerprint hedefinin üstünde) |
| `mcp__abs__code_review` (standard) | 1 | 1 | Webhook full review — 14 issue, 3 HIGH düzeltildi (api_key module-level, seat_count safe parse, jti idempotency check) |
| **TOPLAM MCP çağrısı** | **10** | **7 kullanılabilir** | |

**Tahmini delegation oranı:**
- Delegate edilen kod satırı / toplam yeni kod: **~411 / ~905 ≈ %45** (licensing 185 + activation 105 + webhook 121)
- MCP çağrıları / aksiyon sayısı: bu task'ta ~10 MCP / ~35 aksiyon ≈ **%28**

Hedef %25+ karşılandı. `write_tests` çıktısı kalitesiz olduğu için testleri kendim yazdım (edge-case coverage + TestClient + monkeypatch stripe stub); bu kararın sonucu 12 test geçer durumda.

## Test Sonuçları

```
$ .venv/bin/pytest tests/ -q
............                                                             [100%]
12 passed in 0.57s
```

### Canlı Docker webhook doğrulaması

```
healthz                       → 200 {"status":"ok","service":"abs-backend"}
GET /v1/license/status        → 200 {"status":"unconfigured"}
POST /webhooks/stripe (no sig) → 400 {"detail":"Stripe-Signature header eksik"}
POST /webhooks/stripe (bad)    → 400 {"detail":"İmza doğrulanamadı"}
```

### Manuel roundtrip

```
jti= 1566bf1344f34ee9 ... tier= self-host seat= 1
token_len= 567
```

### Judge patch skoru

`generator.py`: **combined 6.07** / LLM 8.0 / AST 4.78. LLM review: "Clear naming, minimalistic, lacks explicit input validation" — validation Pydantic `LicensePayload`'da yapılıyor (generator girişi tier/seat_count Literal ve `ge=1` ile zaten kontrol ediliyor).

## Code Review'den Uygulanan Düzeltmeler

| # | Sev | Düzeltme |
|---|-----|----------|
| 3 | HIGH | `stripe.api_key`'i module-level'a taşıdım — per-request race önlendi |
| 4 | MED | `_parse_seat_count()` helper — `"abc"` gibi bozuk string → 500 yerine default 1 |
| 1 | HIGH | Idempotency: `select(License).where(jti==…).first()` — aynı jti varsa `duplicate: True` ile 200 döner (stripe retry güvenli) |

## Atlanan (Bilinçli, 003+ task'a taşındı)

- **Async DB session** (HIGH #2) — `AsyncSession` migrasyonu + `BackgroundTasks` email — gerçek trafik gelince optimize edilecek
- **Pydantic response models** (LOW #11) — OpenAPI schema iyileştirme, MVP için gerek yok
- **Request body size limit** (LOW #12) — Caddy reverse proxy seviyesinde yapılabilir
- **Email validation + PII mask** (LOW #8, #13) — marketing/legal paketi ile birlikte ele alınmalı
- **settings.refund_url env'e çıkarma** (LOW #7) — landing URL'leri ile birlikte 003'te
- **`write_tests`'in düzgün çalışmadığı** — CodeLlama çıktısı FastAPI pattern'ini karıştırıyor; summary'e not olarak geçti, task bloklamadı

## Güvenlik Notu

- ✅ RSA 2048 private key `.gitignore`'da (`*.pem`, `core/backend/data/`, `infra/data/`) — repo'ya sızmaz
- ✅ JWT algoritması **RS256** (asimetrik) — müşteri image'ına sadece public key gidecek; private key sadece billing sunucusunda kalır
- ✅ Webhook imzası **zorunlu**: missing sig → 400, bad sig → 400 "İmza doğrulanamadı"
- ✅ `_parse_seat_count` integer parse güvenliği — bozuk metadata 500 üretmez
- ✅ `.env` atomic write (tempfile + `shutil.move` aynı dizinde) — kısmi yazım riski yok
- ✅ SQLite `check_same_thread=False` sadece SQLite için; Postgres'e geçildiğinde devre dışı
- ✅ Email console fallback `smtp_host` boşsa — dev'de gerçek SMTP zorunlu değil, prod'da `ABS_SMTP_HOST` dolu olması gerekiyor

## Notlar Planlayıcıya

1. **003-landing.md** için gerekenler: `refund_url` / `install guide url` placeholder'ları şu an webhook içinde hardcoded (`https://abs.automatiabcn.com/refund`, `abs.automatiabcn.com/docs/install`). Landing domain netleştiğinde `settings.refund_url`, `settings.install_docs_url` env'leri açılmalı.
2. **004-panel.md** veya sonrası için: `/v1/license/activate` şu an açık — panel UI eklenince auth/CSRF korumalı hale getirilmeli. Şu anda yerel (LAN) kabul ediliyor, Caddy sadece LAN'da expose.
3. **Update channel** endpoint'i hâlâ placeholder (`{"channel":"stable","current":"0.1.0"}`) — 005 veya `docs/operations.md`'deki update mekaniği için ayrı task gerekiyor.
4. **Stripe test akışı:** production'a geçmeden önce `stripe listen --forward-to http://localhost:80/webhooks/stripe` ile `stripe trigger checkout.session.completed` end-to-end manuel test yapılmalı. Real test bu task'ta yapılmadı (Stripe CLI + canlı test hesabı gerekir).
5. **MCP delegation notları:**
   - `mcp__abs__fullstack` şu anki prompt büyüklüğünde (>8K tok) TPM limite takılıyor — bu task şablonundaki promptları kısaltmak faydalı olabilir
   - `mcp__abs__write_tests` CodeLlama test kalitesi FastAPI için düşük — custom prompt ile `qual_code` daha iyi sonuç veriyor; şablon güncellenebilir
   - Generator skoru 6.07'nin düşük görünmesinin sebebi AST fingerprint'in "daha kısa docstring + daha az type hint" hedefi; kod kalitesi LLM nezdinde 8/10.
