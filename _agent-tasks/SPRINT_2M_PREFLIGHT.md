# SPRINT 2M — Preflight Notes

**Date:** 2026-05-14
**Branch:** `feat/sprint-2m-customer-e2e-audit` (cut from Sprint 2K HEAD `c68a5a6`)
**ETA:** 6-8 saat (provider key yok → ~4-5 saat partial chain)
**Worker:** Sprint 2M autonomous

---

## A1 — Sprint 2K baseline pytest

```
2143 passed, 24 skipped, 3 deselected, 58 warnings in 220.75s (0:03:40)
```

Brief beklentisi `2143/0/24` — **birebir eşleşti**, regression yok.

## A2 — Provider key envanteri

**Sonuç:** 6/6 provider key (Anthropic, Groq, Gemini, Cerebras, Cohere, OpenAI) hiçbir yerde
yok. Detay + founder paste rehberi → `SPRINT_2M_PROVIDER_KEY_BLOCKED.md`.

STOP CRITERIA #1 partial: FAZ D + F-generation + J → SKIP. FAZ A-C-E(partial)-G-H-I-K-L-M
→ devam.

## A3 — Test ortamı

**Karar:** Lokal docker compose, M4 üzerinde `/tmp/abs-customer-sim/`.

```
/tmp/abs-customer-sim/
├── docker-compose.yml      (infra/docker-compose.customer.yml kopyası)
├── Caddyfile               (infra/Caddyfile.customer kopyası)
├── cerbos/                 (infra/cerbos bundle, config.yaml + policies/)
└── .env                    (chmod 600; license JWT mint edildi, provider keys boş)
```

**.env durum:**

| Key | Durum |
|-----|-------|
| ABS_LICENSE_KEY | ✅ SIM JWT (mint_and_email.sh --dry-run, JTI `3b18a302...`) |
| ABS_PUBLIC_HOSTNAME | ✅ `abs.sim.local` |
| ABS_PUBLIC_URL | ✅ `http://abs.sim.local` (Caddy `tls internal` veya HTTP-only) |
| ABS_ACME_EMAIL | ✅ `sim@example.local` |
| ABS_VAULT_KEY | ✅ `openssl rand -base64 32` |
| ABS_VERSION | ✅ `1.0.0` |
| ABS_NEO4J_PASSWORD | ✅ random suffix |
| 6 provider keys | ❌ boş (FAZ D'ye kadar bekler) |

## A4 — Hetzner test ortamı (Plan B değerlendirmesi)

Brief Plan B: `abs-customer-sim-1` Hetzner CCX23 €26/ay. **Karar:** Lokal compose ile
ilerle (M4 yeterli, ARM build slow değil çünkü image pull edilecek). ACME TLS gerçek
değil — `tls internal` veya HTTP-only OK çünkü audit-only sprint (Lesson 14: no live deploy).

## Sıradaki — FAZ B

1. GHCR pull (`ai-pc:~/keys/github-pat-abs-v3.txt`)
2. `docker compose pull` (backend + landing + email-cron + qdrant + cerbos + neo4j + caddy)
3. `docker compose up -d` + 60s wait
4. Smoke: `/healthz` + `/v1/license/status`
5. Screenshot B1-B4 evidence
