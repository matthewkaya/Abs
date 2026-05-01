# Task 024 — Production Validation + E2E Smoke + Health Hardening

**Status:** READY (Worker autonomous mode)
**Tahmini süre:** 4-6 saat
**Bağımlı task'lar:** 010-023 hepsi
**Hedef:** Sistem **gerçekten** çalışıyor — kod var ama kanıt yok denilemeyecek seviyede e2e doğrulama, tool sağlığı, deployment smoke, Lighthouse tam puan.

---

## 0. Bağlam

010-023 boyunca 376 backend test + 22 frontend test geçiyor, 107 MCP tool register, 22 task spec completed/'da. AMA:
- **Tüm 107 MCP tool gerçekten çalışıyor mu?** (test yazılmış olabilir, ama mock; live çağrı?)
- **3 dil i18n gerçekten 3 farklı response mı veriyor?** (test mock, live HTTP `Accept-Language` ile farklı çıktı?)
- **Setup wizard tam akış 6 adımda biter mi?** (tek tek test var, end-to-end yok)
- **Lighthouse a11y 93 + best-practices 96** — neden 100 değil? (debt kapanmalı)
- **Stripe Customer Portal + Refund** — gerçek webhook ile e2e (test mock)
- **Docker compose up** production-like ortamda hatasız mı?
- **Smart link OAuth flow** — mock callback gerçekten DB'ye yazıyor mu?

024: bu "kod var ama kanıt yok" boşluğunu kapatır. Live HTTP çağrıları + Docker stack smoke + Lighthouse tam puan + tool inventory rapor.

---

## 1. Amaç (DoD)

- [ ] **Tool inventory smoke:** 107 MCP tool'un her biri için "sağlık check" — mock veya minimal gerçek çağrı, ok/fail/skip rapor
- [ ] **i18n e2e:** `Accept-Language: en/tr/es` header ile 3 endpoint × 3 dil = 9 gerçek HTTP çağrı + farklı response doğrulanır
- [ ] **Setup wizard e2e:** 6 adım headless akış (Playwright veya pytest httpx) — start → lang → keys → vault → demo → activate → completed
- [ ] **Stripe e2e (mock):** Checkout session create → webhook simulate → license generate → activate → revoke flow
- [ ] **Smart link e2e (mock):** GitHub OAuth callback simulate → DB encrypted store → list providers
- [ ] **Lighthouse iyileştirme:** a11y 93→100, best-practices 96→100 (eksik leri kapat)
- [ ] **Docker compose up smoke:** `docker compose -f infra/docker-compose.yml up -d` başarılı, all services healthy 60s içinde, `/health` 200, sonra `down`
- [ ] **Health endpoint detaylı:** `/v1/health/full` — her bağımlılık (DB, vault, providers, RAG, MCP) durum
- [ ] 25+ yeni test, pytest 376 → ~401
- [ ] 6 smoke evidence (e2e raporları)
- [ ] Tool count 107 (yeni tool yok bu task'ta — sadece doğrulama)

---

## 2. Modüller

### Modul A — MCP Tool Inventory Smoke
**Yeni:** `infra/scripts/mcp_tool_smoke.py` (~200 satır)
- 107 tool listele (`mcp_server.list_tools()`)
- Her tool için: minimal valid input + call + response shape kontrolü
- Skip listesi: live API gerektirenler (mock'la veya skip işaretle)
- Çıktı: JSON `{tool_name: {ok: bool, latency_ms: int, error: str|null, skip_reason: str|null}}`
- 5 test (`test_mcp_tool_smoke.py`)

### Modul B — i18n End-to-End
**Yeni:** `tests/test_i18n_e2e.py` (~120 satır)
- httpx async client, FastAPI TestClient
- 3 dil × 3 endpoint (license activate, checkout fail, webhook fail) = 9 test
- `Accept-Language: tr-TR;q=0.9,en;q=0.8` parsing doğrula
- Response detail metni dile göre değişmeli (her dil için farklı string fixture)
- 9 test

### Modul C — Setup Wizard End-to-End
**Yeni:** `tests/test_setup_wizard_e2e.py` (~180 satır)
- Sıralı 6 adım: POST step 0 (lang) → 1 (admin email) → 2 (license key veya demo) → 3 (provider keys) → 4 (vault encrypt) → 5 (test connection) → 6 (complete)
- Her step sonrası `GET /v1/setup/state` doğrulama
- Final: `setup_state.completed=True`
- 4 test (happy path, skip step, retry, completion idempotent)

### Modul D — Stripe E2E Flow
**Yeni:** `tests/test_stripe_e2e_flow.py` (~150 satır)
- Mock Stripe API (`monkeypatch`):
  - `Session.create` → fake checkout_url
  - `Webhook.construct_event` → checkout.session.completed payload
  - `charge.refunded` payload (refund flow)
- Adımlar: checkout → webhook (license create + email + DB row) → activate → revoke (refund webhook) → license_status revoked
- 4 test

### Modul E — Smart Link OAuth E2E
**Yeni:** `tests/test_smart_link_e2e.py` (~120 satır)
- Mock GitHub OAuth (`/authorize` redirect URL + `/callback?code=mock`)
- Token exchange mock → DB encrypt + store
- `GET /v1/smart-link/providers` → `github: connected: true`
- API key bağlantı: `POST /v1/smart-link/api-key` provider="openai" + mock key validation
- 4 test

### Modul F — Lighthouse a11y/bp 100
- `core/landing/components/*` — a11y eksiklikleri tespit + fix:
  - `<button>`'lara aria-label
  - `<img>`'lere alt text
  - Form `<label>` eşleşmesi
  - Color contrast (4.5:1 minimum)
  - `<html lang>` attribute
- `next.config.ts` security headers (Content-Security-Policy, X-Frame-Options, X-Content-Type-Options) → best-practices 100
- Yeni Lighthouse evidence (a11y 100 + bp 100 hedef)

### Modul G — Docker Compose Production Smoke
**Yeni:** `infra/scripts/compose_smoke.sh` (~80 satır):
```bash
#!/bin/bash
set -e
cd infra/
docker compose up -d
sleep 30  # services start
# Health checks
for svc in abs-backend abs-caddy abs-vault; do
  status=$(docker compose ps -q $svc | xargs docker inspect -f '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
  echo "$svc: $status"
done
curl -fsS http://localhost:8080/health > /tmp/abs-024-smoke/evidence/06_compose_health.json
docker compose down
```
- 1 test (`test_compose_smoke.py`) — script mevcut + chmod +x doğrula

### Modul H — Health Endpoint Detaylı
**Yeni:** `app/api/health_full.py`
- `GET /v1/health/full` — her bağımlılık check:
  - DB connection (SELECT 1)
  - Vault decrypt test (master key access)
  - Each provider config (env var present, no live call)
  - RAG (chromadb daemon ping)
  - MCP server (`list_tools()` count)
  - Email (SMTP_HOST set veya console fallback)
- Output: `{checks: [{name, ok, detail}], overall: bool}`
- 3 test

---

## 3. Test Stratejisi (25+ test)

| Modül | Test |
|---|:-:|
| A MCP smoke | 5 |
| B i18n e2e | 9 |
| C setup wizard e2e | 4 |
| D Stripe e2e | 4 |
| E smart link e2e | 4 |
| F Lighthouse — fixture test (config + headers) | 2 |
| G compose smoke | 1 |
| H health full | 3 |
| **TOPLAM** | **32** |

Backend: 376 → **408** (+32). Frontend: 22 (değişmez).

---

## 4. Smoke Evidence (`/tmp/abs-024-smoke/evidence/`)

1. `01_mcp_tool_smoke_report.json` — 107 tool ok/fail/skip
2. `02_i18n_e2e.json` — 9 farklı response (3 dil × 3 endpoint)
3. `03_setup_wizard_e2e.json` — 6 adım completion
4. `04_stripe_e2e_flow.json` — checkout → webhook → license → revoke
5. `05_smart_link_oauth.json` — github callback + provider list
6. `06_compose_health.json` — docker compose up + /health
7. `07_lighthouse_desktop_v2.json` — a11y/bp 100 doğrulama
8. `08_lighthouse_mobile_v2.json` — aynı

---

## 5. Adım Adım

```
1. baseline pytest 376 + tool 107
2. Modul A: mcp_tool_smoke.py + 5 test
3. Modul B: i18n e2e + 9 test
4. Modul C: setup wizard e2e + 4 test
5. Modul D: Stripe e2e + 4 test
6. Modul E: smart link e2e + 4 test
7. Modul F: Lighthouse a11y/bp fix + new evidence
8. Modul G: compose smoke script + 1 test
9. Modul H: health full endpoint + 3 test
10. Smoke: 8 evidence dosyası
11. summary + completed/
```

## 6. DoD Checklist

```
[ ] 8 modül A-H tamam
[ ] pytest 408 (+32)
[ ] vitest 22 (değişmez, frontend modul yok)
[ ] tool count 107 (yeni tool yok)
[ ] Lighthouse a11y ≥ 100 + bp ≥ 100 (perf+seo zaten 100)
[ ] 8 smoke evidence valid
[ ] Docker compose up smoke OK
[ ] backend regression yeşil (010-023)
[ ] summary + completed/
```

## 7. Worker Notları

1. **Live API çağrısı YOK** — Stripe/OpenAI/Anthropic/GitHub mock. Sadece compose smoke local Docker'da.
2. **Lighthouse a11y debt:** muhtemelen `<button onclick>` aria-label eksik, `<img>` alt eksik, color contrast bazı yerlerde 4.5:1 altında. Inspector ile spot tespit, fix, retest.
3. **best-practices 96 → 100:** Genelde Content-Security-Policy header eksik veya HTTPS-only headers eksik. `next.config.ts` security headers ekle.
4. **MCP smoke tool'lar:** Bazı tool'lar Stripe key veya provider key gerektirir → skip işaretle, neden yazıldı log. Hedef: ok+skip = 107, fail = 0.
5. **i18n e2e:** Mevcut `app/i18n/locales/{en,tr,es}.json` zaten dolu (023). Test sadece `Accept-Language` header'ının doğru locale'i seçtiğini gösterir.
6. **Compose smoke:** Docker Desktop M4 Mac'te çalışıyor, image build adımı 5+ dakika sürebilir. Test cache'li build kullansın.
7. **Health full:** Mevcut `health_status` MCP tool'u (014'ten) farklı — bu daha kapsamlı, deployment-aware.
8. **Memory snapshot:** task sonu `session_resume_state_20260427_024.md` yaz.

---

## DoD Final
```
[ ] 8 modül A-H ✅
[ ] pytest 408
[ ] tool 107
[ ] Lighthouse a11y 100, bp 100
[ ] 8 smoke evidence /tmp/abs-024-smoke/evidence/
[ ] regression sıfır
[ ] summary + completed/
[ ] memory snapshot 024
```
