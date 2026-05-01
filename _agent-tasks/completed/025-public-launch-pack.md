# Task 025 — Public Launch Pack (GitHub + Beta + Deploy + Status + Discord)

**Status:** READY (Worker autonomous mode — first of 2-task chain 025→026)
**Tahmini süre:** 4-5 saat
**Bağımlı task'lar:** 010-024 hepsi
**Hedef:** Ürünü **public launch'a hazır** hale getir — GitHub repo template, beta lisans generator, production deploy script, status page, Discord webhook.

---

## 0. Bağlam

Ürün 024 sonunda launch-ready (Lighthouse 100/100/100/100, 409 test, 107 tool). Eksik kalan: **dış dünyaya açılma** araçları. GitHub repo public yapıldığında müşteri/contributor karşılaşacağı dosyalar (README, LICENSE, CONTRIBUTING) hazır olmalı. Beta tester pakete erişim manuel ama tekrarlanabilir olmalı. Hetzner gibi VPS'te 1 komutla kurulum + hazır status page.

---

## 1. Amaç (DoD)

- [ ] **README.md final** (~600 kelime EN, hero CTA + features + 15dk install + pricing + license)
- [ ] **LICENSE** Apache 2.0
- [ ] **CONTRIBUTING.md** + **CODE_OF_CONDUCT.md** + **SECURITY.md**
- [ ] **GitHub templates:** `.github/ISSUE_TEMPLATE/{bug.yml,feature.yml,question.yml}` + `pull_request_template.md`
- [ ] **Beta lisans generator:** `infra/scripts/generate_beta_license.py` — JWT + DB row + email send (3 SKU desteği)
- [ ] **Production deploy script:** `infra/scripts/deploy_hetzner.sh` (~150 satır, bash idempotent)
- [ ] **Status page:** `GET /v1/status` (JSON) + `app/static/status.html` (auto-refresh JS)
- [ ] **Discord webhook integration:** `app/integrations/discord_webhook.py` — license/refund/health alert
- [ ] **MCP tool:** `status_check` (system + recent activity)
- [ ] 20+ yeni test, pytest 409 → ~432
- [ ] Tool count 107 → 108
- [ ] 5 smoke evidence

---

## 2. Modüller

### Modul A — Public Repo Files
- `README.md` (TR ve EN; varsayılan EN, `README.tr.md` link)
- `LICENSE` (Apache 2.0 standard)
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md`
- `.github/ISSUE_TEMPLATE/{bug.yml, feature.yml, question.yml}` YAML form
- `.github/pull_request_template.md`
- 3 test (`test_repo_files_exist.py`)

### Modul B — Beta Lisans Generator
**Yeni:** `infra/scripts/generate_beta_license.py` (~200 satır)
- CLI: `python generate_beta_license.py --email x@y.com --tier self-host --duration-days 180`
- JWT generate (mevcut `app/licensing/generator.py`)
- DB row insert (`License` table, `customer_id_stripe='beta:...'`)
- Email gönder (mevcut `send_license_email`, beta_invitation.html template)
- Yeni template: `app/email/templates/beta_invitation_{en,tr,es}.html`
- Output stdout: `LICENSE=eyJ...`
- 4 test (`test_beta_license_generator.py`)

### Modul C — Production Deploy Script
**Yeni:** `infra/scripts/deploy_hetzner.sh` (~150 satır)
- Idempotent: install Docker + docker-compose, clone repo, copy .env.example → .env, vault init, compose up
- Args: `--domain abs.example.com --email admin@example.com --skip-tls`
- Caddy auto TLS (Let's Encrypt)
- Hetzner cloud-init `cloud-init.yml` opsiyonel
- 1 test (script syntax + chmod check)

### Modul D — Status Page
**Yeni:** `app/api/status_page.py`
- `GET /v1/status` → `{services: [...], overall: ok|degraded|down, uptime_seconds, version}`
- 7 service check (DB, vault, providers, RAG, MCP, email, stripe)
- `app/static/status.html` — vanilla HTML/CSS, 30s auto-refresh fetch `/v1/status`
- Brand-aligned (Automatia mavi, JetBrains Mono)
- 4 test

### Modul E — Discord Webhook
**Yeni:** `app/integrations/discord_webhook.py` (~100 satır)
- `notify_license_purchased(jti, email, tier)` — Discord embed
- `notify_refund(jti, reason)`
- `notify_health_alert(service, error)`
- `settings.discord_webhook_url` (env, opsiyonel — boşsa sessiz no-op)
- Webhook entegrasyonu: `webhooks/stripe.py` `checkout.session.completed` sonunda + `charge.refunded` sonunda
- 4 test (mock httpx, env yok → no-op, signature)

### Modul F — `status_check` MCP Tool
**Yeni:** `app/mcp/tools/status_tools.py`
- `status_check()` — `/v1/status` shape + last 24h key metrics (license_count, revenue_today_usd, recent_errors)
- 2 test
- Tool count 107 → **108**

### Modul G — README Final
- 600 kelime EN (delegation: `ask "..." gptoss`)
- Hero: "Self-host AI orchestration for Claude Code"
- Features bullet list (75+ MCP tools, 6 providers, RAG hybrid, Türkçe quality)
- Quick install (Docker compose 1-liner)
- Pricing table (3 SKU)
- License + Community badge
- Test: word count + section presence (`test_repo_files_exist.py` extend)

---

## 3. Test Stratejisi (20 test)

| Modül | Test |
|---|:-:|
| A repo files | 3 |
| B beta license | 4 |
| C deploy script | 1 |
| D status page | 4 |
| E discord webhook | 4 |
| F status_check MCP | 2 |
| Tool count guard | (1 update) |
| README contents | 2 |
| **TOPLAM** | **20** |

Backend: 409 → **429** (+20). Tool: 107 → **108**.

---

## 4. Smoke Evidence (`/tmp/abs-025-smoke/evidence/`)

1. `01_repo_files.json` — README/LICENSE/CONTRIBUTING/CoC/Security exist + word counts
2. `02_beta_license_generated.json` — script output (JWT + DB row + email console fallback)
3. `03_status_page.json` — `/v1/status` response
4. `04_discord_webhook_payload.json` — mock httpx call captured
5. `05_status_check_mcp.json` — MCP tool response

---

## 5. Adım Adım

```
1. baseline pytest 409 + tool 107
2. Modul A: repo files + 3 test (README delegation: gptoss)
3. Modul B: beta_license generator + email template (3 dil) + 4 test
4. Modul C: deploy_hetzner.sh + 1 syntax test
5. Modul D: status_page endpoint + HTML + 4 test
6. Modul E: discord_webhook + webhook integration + 4 test
7. Modul F: status_check MCP + 2 test + count 107→108
8. Modul G: README final word count + 2 test
9. Smoke 5 evidence
10. summary + completed/
11. Memory snapshot session_resume_state_20260427_025.md
12. (DEVAM) 026'ya geç (autonomous chain)
```

## 6. DoD Checklist

```
[ ] Modul A-G tamam
[ ] pytest 429
[ ] tool 108
[ ] 5 smoke evidence valid
[ ] regression sıfır (010-024)
[ ] summary + completed/
[ ] memory snapshot 025
```

## 7. Worker Notları

1. README EN ana dil; TR çeviri opsiyonel (`README.tr.md` skeleton, sonra doldurulur).
2. `LICENSE` Apache 2.0 standard text — `https://www.apache.org/licenses/LICENSE-2.0.txt`.
3. Beta lisans script DB'ye `customer_id_stripe='beta:<email_hash>'` formatı.
4. Discord webhook URL boşsa **no-op** (boot crash yok). Env: `ABS_DISCORD_WEBHOOK_URL`.
5. Status page polling 30s (CPU dostu); 5s opsiyonel.
6. Hetzner deploy script `set -euo pipefail`, her step idempotent (`docker stat ... || install`).
7. ISSUE_TEMPLATE YAML format Github 2024+ standardı (markdown form).
8. CONTRIBUTING.md "fork → branch → PR → 2 review → merge" akışı.
9. Live deployment YAPMA — script hazır, kullanıcı manuel koşacak.
10. Memory snapshot 025 yazıldıktan sonra **026 spec'ini oku ve autonomous devam et** (master prompt'ta yazılı).
