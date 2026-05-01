# Task 002 — Licensing: Stripe Webhook + JWT Lisans Key

## Bağlam

Müşteri `abs.automatiabcn.com`'dan "Buy Now" ($299) basar → Stripe Checkout → ödeme başarılı → ABS lisans key üretir → email'e gönderir → müşteri panel'de key'i girer → sistem aktifleşir.

Bu task o akışın **backend kısmını** kurar. Frontend (landing, pricing sayfası, Stripe Checkout button) 003. task'ta yazılacak.

**Bağlı docs:**
- `docs/research/one-time-license.md` — JWT pattern, Stripe webhook akışı, fiyatlandırma
- `docs/design-decisions.md` § 8 ve § 12 — revenue + Stripe kararları

**Kaynaklar:** SERVER'da lisans mekaniği **YOK**. Bu task tamamen scratch. Referans: Stripe webhook docs + PyJWT RFC 7519.

## Giriş (Mevcut Durum — 001 sonrası)

- `core/backend/app/main.py` — FastAPI app + `/healthz` + **placeholder** `/v1/license/status`
- `core/backend/app/config.py` — Pydantic Settings (env `ABS_LICENSE_KEY` tanımlı)
- `pyproject.toml` — FastAPI + uvicorn + pydantic-settings + sqlmodel
- Test altyapısı: pytest + httpx

## Beklenen Çıktı

### 1. Lisans üretici servis (bizim taraf, `core/backend/app/licensing/`)

Bu modüller **hem bizim hem müşteri tarafında** kullanılır. Bizim tarafta üretim (private key ile imza), müşteri tarafında **doğrulama** (public key ile).

- [ ] `app/licensing/__init__.py`
- [ ] `app/licensing/keys.py` — RSA key pair oluşturucu/loader (`ABS_PRIVATE_KEY_PATH`, `ABS_PUBLIC_KEY_PATH`)
- [ ] `app/licensing/generator.py` — `generate_license(customer_id, tier, seat_count, valid_until) -> str (JWT)`
- [ ] `app/licensing/verifier.py` — `verify_license(token) -> dict` (public key ile doğrula, expired check, schema validate)
- [ ] `app/licensing/schemas.py` — Pydantic `LicensePayload` (customer_id, tier, seat_count, iat, exp, jti)

### 2. Stripe Webhook (bizim taraf, `core/backend/app/api/webhooks/`)

- [ ] `app/api/webhooks/__init__.py`
- [ ] `app/api/webhooks/stripe.py` — `POST /webhooks/stripe` endpoint
  - Stripe signature doğrulama (`stripe.Webhook.construct_event`)
  - `checkout.session.completed` event dinleme
  - Customer bilgilerini oku (email, amount, metadata)
  - `generate_license()` çağır
  - DB'ye kaydet (`licenses` tablosu)
  - Email gönder (aşağıda)

### 3. DB (SQLModel)

- [ ] `app/db/__init__.py`
- [ ] `app/db/models.py` — `License` model: `id, jti, customer_email, customer_id_stripe, tier, seat_count, issued_at, expires_at, revoked_at, revoked_reason`
- [ ] `app/db/session.py` — SQLite engine + session dependency (FastAPI injection)
- [ ] `alembic.ini` veya basit `create_all()` startup hook (MVP için `create_all` yeter)

### 4. Email gönderici

- [ ] `app/email/__init__.py`
- [ ] `app/email/sender.py` — SMTP config (env `ABS_SMTP_*`) + send fonksiyonu
- [ ] `app/email/templates/license_delivery.html` — Türkçe email template (satın alma teşekkürü + key + kurulum linki)

**Not:** MVP için SMTP yerine **console log fallback** kabul edilebilir (test için); gerçek SMTP config'i development sırasında placeholder kalabilir.

### 5. Müşteri tarafı aktivasyon endpoint

- [ ] `app/api/license.py` — `POST /v1/license/activate` endpoint
  - Body: `{"license_key": "eyJ..."}`
  - `verify_license()` çağır
  - Valid ise `settings.license_key`'i güncelle (runtime + `.env` persist)
  - Invalid ise 400 + hata mesajı
- [ ] Mevcut `/v1/license/status` placeholder'ını gerçeğe çevir:
  - Status: "active" | "expired" | "unconfigured" | "revoked"
  - Seat count, tier, expires_at döndür

### 6. Test

- [ ] `tests/test_licensing.py`
  - `test_generate_and_verify_license()` — roundtrip (üret → doğrula → payload eşleşsin)
  - `test_expired_license_rejected()` — expired token 400 döner
  - `test_invalid_signature_rejected()` — tampered token 400
- [ ] `tests/test_stripe_webhook.py`
  - `test_webhook_signature_required()` — imza yoksa 400
  - `test_checkout_completed_generates_license()` — mock Stripe event → DB'de license oluşmalı, email console log'a düşmeli

### 7. Konfigürasyon

- [ ] `app/config.py` güncelle — yeni env'ler:
  - `ABS_STRIPE_SECRET_KEY`
  - `ABS_STRIPE_WEBHOOK_SECRET`
  - `ABS_PRIVATE_KEY_PATH` (default: `/app/data/private.pem`)
  - `ABS_PUBLIC_KEY_PATH` (default: `/app/data/public.pem`)
  - `ABS_SMTP_HOST`, `ABS_SMTP_PORT`, `ABS_SMTP_USER`, `ABS_SMTP_PASSWORD`
  - `ABS_DATABASE_URL` (default: `sqlite:////app/data/abs.db`)
- [ ] `infra/.env.example` güncelle

## Kısıtlar

- ❌ SERVER klasörüne dokunma
- ❌ Scope dışı eklemeler (enterprise multi-seat UI, licence marketplace vb. — sonraki task)
- ❌ Email template'i marketing dolu yazma — şeffaf + net TR
- ✅ JWT RS256 (asimetrik) — HS256 (simetrik) KABUL DEĞİL
- ✅ Stripe `stripe` Python kütüphanesi (pyproject'e eklensin)
- ✅ PyJWT (`PyJWT[crypto]>=2.9`) + `cryptography`
- ✅ SQLModel (pyproject'te zaten var)
- ✅ pytest + httpx (webhook mock için `respx` veya Stripe'ın kendi test modu)
- ✅ Tüm test yeşil olmadan `completed/`'e taşıma yapma

## Delegation Yönergesi (ZORUNLU — README kuralı)

Bu task uzun kod içerir. **Kendi başına yazma.** ABS MCP tool'larını kullan:

### 1. Benzer patternler için SERVER RAG ara
```
mcp__abs__rag_query "stripe webhook signature verification python fastapi"
mcp__abs__rag_query "pyjwt rs256 generate verify"
```

### 2. JWT generator + verifier için `qual_code` kullan
```
mcp__abs__qual_code
  prompt: "Python 3.11 FastAPI için JWT license module yaz:
  - generate_license(customer_id, tier='self-host', seat_count=1, valid_days=365) -> str
  - verify_license(token: str) -> dict (expired ise HTTPException 401)
  - RS256, PyJWT[crypto], private/public key file-based
  - Pydantic v2 LicensePayload schema
  - Docstrings TR
  
  Gerekli import'lar + tip ipuçları + hata mesajları TR."
```

### 3. Stripe webhook için `fullstack` backend layer
```
mcp__abs__fullstack
  prompt: "FastAPI endpoint: POST /webhooks/stripe
  - stripe.Webhook.construct_event ile imza doğrula (env ABS_STRIPE_WEBHOOK_SECRET)
  - checkout.session.completed event'inde: customer email, amount, metadata'dan tier oku
  - app.licensing.generator.generate_license çağır (dependency injection)
  - License DB'ye insert (SQLModel Session)
  - Email sender async çağır (console log fallback dev'de)
  - Başarılı: 200 {status: ok, jti: ...}
  - Hata: Stripe spec uygun retry code"
  layer: "be"
```

### 4. Email template için `qual_tr`
```
mcp__abs__qual_tr
  prompt: "Stripe satın alma sonrası gönderilecek Türkçe email template. Plain HTML.
  
  İçerik:
  - Otomatia ABS aldığın için teşekkür
  - 'Lisans anahtarın:' + {{ license_key }} (monospace block)
  - Kurulum rehberi linki: abs.automatiabcn.com/docs/install
  - 14 gün iade: {{ refund_url }}
  - Destek: support@automatiabcn.com
  - Alt: Automatia BCN imza
  
  Samimi ama profesyonel. Marketing claim yok."
```

### 5. Test yazımı için `write_tests`
```
mcp__abs__write_tests
  function_signatures: "generate_license, verify_license, stripe_webhook_endpoint"
  prompt: "Edge case'ler dahil: expired, tampered signature, missing env, valid roundtrip, webhook imza yok, unknown event type."
```

### 6. Final patch skorla
Tüm kod yazıldıktan sonra:
```
mcp__abs__judge_patch
  unified_diff: <git diff çıktısı>
  file_path: "app/licensing/generator.py"
```

Skor < 7 ise `mcp__abs__code_review` tier=standard ile bak, düzelt.

### Hedef Delegation

- Bu task'ta en az **%25 delegation** (uzun kod + TR email + test + skorlama)
- `mcp__abs__*` çağrıları minimum 5-6 kez

## Adımlar (sıra önemli)

1. **Önce research:** `mcp__abs__rag_query` ile Stripe/JWT benzer örnekler (varsa)
2. **pyproject.toml güncelle:** `stripe>=10`, `PyJWT[crypto]>=2.9`, `cryptography>=43`, SQLModel zaten var
3. **Config:** yeni env'leri `app/config.py` + `.env.example` ekle
4. **DB model:** `app/db/models.py` + `session.py` + startup hook `create_all`
5. **Licensing:** keys + generator + verifier + schemas (`qual_code` delege)
6. **Stripe webhook:** endpoint (`fullstack be` delege)
7. **Email:** sender + template (`qual_tr` delege template için)
8. **Aktivasyon endpoint:** `POST /v1/license/activate` + `GET /v1/license/status` güncellemesi
9. **main.py:** yeni router'ları register et
10. **Testler:** `test_licensing.py`, `test_stripe_webhook.py` (`write_tests` delege)
11. **Doğrulama:** `.venv/bin/pytest tests/ -q` → yeşil
12. **Patch skoru:** `mcp__abs__judge_patch` → >= 7
13. **Summary:** `completed/002-licensing-summary.md` yaz — **Delegation Kullanımı** bölümü zorunlu

## Doğrulama

```bash
# 1. Bağımlılık install
cd core/backend
.venv/bin/pip install -e ".[dev]"

# 2. RSA key çifti oluştur (dev, .gitignore'da)
mkdir -p data/
openssl genrsa -out data/private.pem 2048
openssl rsa -in data/private.pem -pubout -out data/public.pem

# 3. Unit testler
.venv/bin/pytest tests/ -q
# Beklenen: en az 8 passed (1 smoke + 4 licensing + 3 webhook)

# 4. License roundtrip manual
.venv/bin/python -c "
from app.licensing.generator import generate_license
from app.licensing.verifier import verify_license
token = generate_license('cust_test_001', tier='self-host', seat_count=1)
payload = verify_license(token)
print('OK:', payload)
"
# Beklenen: OK: {customer_id: 'cust_test_001', tier: ..., exp: ...}

# 5. Docker build (yeni deps geldi)
cd ../../infra
docker compose build backend
# Beklenen: stripe + pyjwt + cryptography kurulur

# 6. Stripe webhook curl mock (dev)
docker compose up -d
curl -X POST http://localhost:80/webhooks/stripe \
  -H "Stripe-Signature: <invalid>" \
  -d '{"type":"checkout.session.completed"}'
# Beklenen: 400 invalid signature
```

## Tamamlama

Bitirince:

1. `git diff` çıktısı al (görsel review için)
2. `mcp__abs__judge_patch` ile diff'i skorla, sonucu summary'ye ekle
3. `completed/002-licensing-summary.md` yaz:
   ```markdown
   # Task 002 Summary

   ## Ne Yapıldı
   [dosya listesi + satır sayıları]

   ## Delegation Kullanımı
   - mcp__abs__rag_query: N kez
   - mcp__abs__qual_code: N kez
   - mcp__abs__fullstack: N kez
   - mcp__abs__qual_tr: N kez
   - mcp__abs__write_tests: N kez
   - mcp__abs__judge_patch: N kez
   - Toplam delegation oranı: %X (hedef %25+)

   ## Atlanan / Blocker
   [varsa]

   ## Test Sonuçları
   - pytest: X passed
   - Judge patch skoru: Y/10
   - Docker build: OK/FAIL

   ## Güvenlik Notu
   - Private key `.gitignore`'da
   - Webhook signature zorunlu
   - JWT RS256, HS256 değil

   ## Notlar Planlayıcıya
   [gelecek task'lara etki, karar bekleyen konular]
   ```
4. Bu task dosyasını `_agent-tasks/completed/002-licensing.md` olarak taşı
5. Planlayıcıya "002 tamam" rapor et

---

**Tahmini süre:** 2-3 saat (delegation sayesinde 3-4 saat yerine)
**Sonraki task:** `003-landing.md` — Next.js landing + Stripe Checkout button (abs.automatiabcn.com subdomain)
