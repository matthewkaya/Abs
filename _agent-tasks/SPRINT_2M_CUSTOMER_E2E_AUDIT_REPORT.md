# Sprint 2M — Customer E2E Audit Comprehensive Report

**Date:** 2026-05-14
**Sprint:** 2M Customer E2E Audit
**Branch:** `feat/sprint-2m-customer-e2e-audit` (cut from Sprint 2K HEAD `c68a5a6`)
**Predecessor:** Sprint 2K Postgres RLS COMPLETE (2143 pytest baseline GREEN)
**Worker:** autonomous chain (M4 lokal docker compose, audit-only)
**Süre:** ~3 saat zincir (provider key yok → STOP CRITERIA #1 partial → FAZ D+F-gen+J SKIP)

---

## 🎯 Müşteri perspektif manifesto

Bu audit'te worker bir **müşteri** rolünü oynadı: Türkiye'de orta ölçekli inşaat firması
kurucusu, teknik yarı-yetkin, $299 ödeyip ABS'i kendi VPS'ine kuran kişi. Her adımda
"ben olsam ne hisseder, ne görür, ne kırılır" sorusu rehber oldu. Bulgular yalın teknik
log değil — UX impact + müşteri davranış tahmini ile birlikte raporlanıyor.

Audit lokal docker compose ortamında yapıldı (M4 Apple Silicon, `/tmp/abs-customer-sim/`).
Founder'ın 6 sağlayıcı API key'i (Anthropic, Groq, Gemini, Cerebras, Cohere, OpenAI)
ai-pc'de bulunamadı, M4 lokal'de de yoktu — bu durum FAZ D (provider ping), FAZ F'in
generation alt-kümesi (38 ask_* tool) ve FAZ J (çıktı kalitesi / Türkçe 50 prompt)
adımlarının skip edilmesine yol açtı. Provider gerektirmeyen 7 FAZ (A, B, C, E, G, H, I,
K, L, M) tam koşturuldu.

---

## 📋 13 FAZ özet

**FAZ A — Preflight + provider key inventory.** Branch cut, Sprint 2K baseline pytest
`2143 / 0 / 24 / 58 warn` GREEN (regression yok). `ai-pc:~/keys/` listing → 6 provider
key dosyası YOK (sadece CF license, GitHub PAT, Hetzner, Resend, manifest signing). M4
`/Users/eneseserkan/keys/` klasörü da yok. STOP CRITERIA #1 partial trigger →
`SPRINT_2M_PROVIDER_KEY_BLOCKED.md` yazıldı, founder paste talep edildi. Test ortamı:
lokal compose `/tmp/abs-customer-sim/`, SIM license JWT mint edildi (JTI `3b18a302...`).

**FAZ B — Customer install simülasyonu.** GHCR docker login (`github-pat-abs-v3.txt`
stdin pipe, Lesson 13 enforce). `docker compose pull` 6 image (backend + landing +
email-cron + qdrant + cerbos + neo4j + caddy). `docker compose up -d` → 7/7 service
running, 5 healthy + 2 healthcheck'siz (qdrant/caddy normal). Smoke: `/healthz` 200
JSON OK; `/v1/license/status` 307 redirect → `/setup` HTML (pre-setup first-run
middleware, beklenen). Caddy edge HTTPS `tls internal` patch lazım oldu (Bug 2M-002 —
ACME default DNS olmadan smoke imkansız). 5 bug bulgu: 1 P0 (setup HTML "Ileri" Türkçe
ihlali), 3 P2, 1 P3.

**FAZ C — Setup wizard 6-step LIVE E2E.** 6 step API sequential:
admin → license → domain → anthropic → providers → test. Tamamlanma 53 saniyede.
`completed_steps: [admin, license, domain, anthropic, providers, test]`. First-run
middleware off (`/v1/license/info` 200 JSON, tier=self-host, expires_at=2027-05-14).
Admin login `/auth/login` 200 + `abs_session` JWT cookie (HttpOnly, SameSite=strict,
7d). Brief'in `/panel/*` route'ları 404 — canonical `/admin/*` (Bug 2M-009 P1 polish
memory v1.7 stale). Step 4 anthropic ping disabled ("live ping disabled in setup") —
format-only validation, müşteri yanlış key paste eder setup tamamlanır (P2 #008).
+5 bug → toplam 10.

**FAZ D — 6 provider live ping + quota_status audit. SKIP.** Provider key yok.
`SPRINT_2M_PROVIDER_KEY_BLOCKED.md` brief'inde belirtildi. quota_status FAZ G'de
audit edildi (5 free unconfigured + 1 fake configured = effectively 6 down).
Founder paste sonrası ayrı sprint (Sprint 2M-Provider-Live veya 2N hot-fix dahil).

**FAZ E — First MCP + RAG + Türkçe byte-exact (cascade chat SKIP).**
`mcp_server._tool_manager._tools` registry → **122 tool** (brief 123 hedef, 1 eksik;
2M-011 P3 minor inconsistency, STOP CRITERIA #8 eşiği <80 değil). MCP HTTP Streamable
transport `/mcp/` JSON-RPC test edildi — curl ile zor (SSE response, Content-Length: 0;
external host header 421 Invalid Host validation aktif Q12 hardening). RAG ingest 215ms
(JSON body, brief multipart örneği stale — 2M-012 P3). RAG query 18ms, doc retrieval
exact match. **Türkçe RAG round-trip:** ingest `"ABS, İstanbul merkezli Automatia
BCN..."` → query `"İstanbul Şubat şirket"` → 8/8 Türkçe karakter (İ,Ş,ş,ğ,ı,ö,ü,ç)
byte-exact PASS ✅ **Lesson 11 storage layer GREEN**. +3 bug → toplam 13.

**FAZ F — 122 MCP tool kategorik deep test.** 14 kategori inventory (38 generation,
28 other, 18 system, 9 judge, 6 quality_pipeline, 5 rag, 4 race, 4 fullstack, 3
codequality, 2 audit, 2 learning, 1 cost, 1 vault, 1 workflow). 51 provider-required
tool SKIP (38 ask_* + 6 qual + 4 race + 3 codeq). 22 provider-free tool invoked:
**20 GREEN (90.9%)**, 2 NEEDS_ARGS (spec gereği). Latency p50=2.5ms, p95=315ms,
outlier rag_status 423ms (Bug 2M-015 P2). **Kritik P1 bug:** `daily_cost` IndexError:4
exception (2M-014) — customer-facing cost tool çalışmıyor. +3 bug → toplam 16.

**FAZ G — Cascade quality + fallback + breaker + 6-down 503.** Brief 4 endpoint stale
(`/v1/chat`, `/v1/cascade/test`, `/v1/admin/cascade/breaker`, `/v1/admin/providers/circuit_state` → 404/405; canonical `/v1/chat/completions`, `/v1/admin/providers/status`,
`/v1/system/quota_status`). 5x cascade 6-down sim sequential → **HTTP 200 + SSE stream**
(brief 503 beklentisi karşılanmadı, Bug 2M-018 P1). SSE event chain: session → pipeline
(`auto_direct`) → thinking → text(provider:`none`) → [DONE]. ✅ Stack leak YOK (UAT-044
P0 koşul OK — 500 değil). **KRİTİK P0 bug:** Fallback message
`"Tum saglayicilar gecici hata verdi; lutfen tekrar deneyin."` —
**8 Türkçe karakter ASCII'ye düşmüş** (Ü→u, ü→u, ğ→g, ç→c, ı→i, ş→s). Lesson 11 byte-exact
FAIL (2M-017). Olması gereken: `"Tüm sağlayıcılar geçici hata verdi; lütfen tekrar deneyin."`
Cascade fallback chain + breaker open/close G5 SKIP (provider key gerektirir). +3 bug → toplam 19.

**FAZ H — Admin panel + KVKK 2-step + data export + audit pagination.**
`/admin/*` 15 sayfa: 13×200 + 2×308 redirect (meetings, transcription). KVKK
`/v1/me/account/delete-request` (Bearer license JWT auth, NOT admin cookie) →
200 OK + `confirm_token` plaintext body (`settings.env != "prod"` intended dev
behavior, 2M-022 P2 — quickstart `ABS_ENV=prod` enforce eksik).
`delete-confirm`, `delete-cancel` → 404 (SIM dry-run mint, DB row yok — beklenen).
**`/v1/me/account/deletion-status` → 404!** Code'da var ama container'da YOK:
**Bug 2M-023 P1** — `ghcr.io/enzoemir1/abs-backend:1.0.0` STALE, me_account.py
container'da 240 satır vs lokal repo 355 satır (Sprint 2I UAT-038 decorator yok).
Data export `/v1/me/data-export` → 200 done, 2060 bytes encrypted blob (`*.zip.enc`)
— KVKK encrypted-at-rest semantics ✅. Audit pagination `/v1/admin/audit/recent`
?limit=100 + ?limit=9999 → 6 entries (cap=100 enforce OK; sim seed sparse 2M-021 P2).
**Bug 2M-020 P1:** Caddyfile @backend pattern listesinde `/me/*` yok → eski API
client'lar landing Next.js 404 alır. +4 bug → toplam 23.

**FAZ I — Edge cases + negative tests.** **3 KRİTİK BULGU:**
**(1) Bug 2M-025 P0** — UAT-009 fail-closed BROKEN: `docker compose stop backend`
sonrası `GET /admin/dashboard` → **200 + 34KB Next.js HTML render**. Landing SSR
auth/health check yok, backend down olsa da müşteri panel'in shell'ini görür.
**(2) Bug 2M-024 P1** — UAT-041 rate limit BROKEN: 10x sequential POST `/auth/login`
wrong password → tümü 401, **0x 429**. Brute force korumasız.
**(3) Bug 2M-026 P0** — Sprint 2K Postgres RLS aktif değil customer compose'da!
Sim DB URL: `sqlite:////app/data/abs.db`. Customer compose `DATABASE_URL` unset →
SQLite fallback. Sprint 2K defense-in-depth katmanı kaybediliyor, tenant izolasyonu
sadece app-level (Cerbos + ORM). License invalid 409 (state machine OK), `/v1/admin/users`
RLS app-level GREEN (cross-tenant filter aktif). Formula injection SKIP (excel endpoint
yok, sibling project). +3 bug → toplam 26.

**FAZ J — Çıktı kalitesi assessment. SKIP.** Provider key yok → cascade chat 50 prompt
Türkçe + judge ML accuracy + RAG grounding (cross-doc query) + cost log audit yapılamadı.
**Partial bulgular:**
- Türkçe karakter RAG storage layer: 8/8 byte-exact ✅ (FAZ E)
- Cascade fallback: Lesson 11 FAIL (Bug 2M-017 P0)
- Setup wizard HTML: Lesson 11 FAIL (Bug 2M-003 P0)
- Net UI critical paths Türkçe pass rate: ~0% (2 P0)
- MCP system tools p50=2.5ms p95=315ms — performans hedefi 9/10
- daily_cost tool fail (P1) — cost log audit imkansız

**FAZ K — Customer UX scorecard + setup time.** 8 kategori puanlama 1-10:
Setup wizard 7, Hata mesajı TR 4, Doc 5, Response N/A, Performance 9, Türkçe 3,
Mobil N/A, KVKK/güven 6. Ortalama (6 kategori) **5.7/10** — "fonksiyonel ama
kalite eksikleri, müşteri 1-2 damga sonrası pes edebilir". Setup time gerçek ölçüm:
container created 21:42:17 → wizard completed 21:48:10 = **~3-8 dakika** (cached vs
cold image pull). Brief hedef ≤30 dk → EXCELLENT timing (%10-25). Müşteri yolculuğu:
ilk 5 dk pozitif first impression, 5-7 dk içinde 3 damga (Türkçe fail, daily_cost
bug, rate limit yok) → pilot güveni sarsılır.

**FAZ L — Bug log + recommendations.** 26 toplam: **4 P0 + 6 P1 + 10 P2 + 6 P3**.
Top 5 founder rec dokümante edildi: (1) Türkçe Lesson 11 blanket-audit + CI gate,
(2) Postgres RLS customer compose entegre, (3) UAT-009 fail-closed landing SSR
restore, (4) Image `1.0.0` → `1.0.1` retag (UAT-038 deletion-status), (5) `/auth/login`
rate limit middleware (UAT-041). Sprint 2N hot-fix önerisi (1-2 hafta) → Pilot Batch 2
GO/NO-GO: **NO-GO** mevcut durumda (4 P0 açık).

**FAZ M — Comprehensive report + cert footer.** Bu doküman + cert footer 🟡 RC
damga (🟢 GREEN eligible değil) + closeout commit.

---

## 📊 Evidence + commit log

**Evidence dump:** 11 text dosyası `_agent-tasks/SPRINT_2M_EVIDENCE/` (~24 KB toplam),
Playwright PNG screenshot terminal-only audit nedeniyle değiştirildi (Playwright headed
mode time-budget dışı, FAZ C HTML response parse + curl evidence ile karşılandı).

| Faz | Evidence dosyası | Boyut |
|-----|------------------|-------|
| B | b1-env-doldur.txt + b2-ghcr-pull + b3-compose-up + b4-smoke | 2 KB |
| C | c-setup-wizard-6step + c-admin-login-panel-route | 3.4 KB |
| E | e-mcp-rag-tr | 2.1 KB |
| F | f-mcp-tool-audit | 3.4 KB |
| G | g-cascade-6down-audit | 2.4 KB |
| H | h-admin-panel-kvkk-audit | 2.7 KB |
| I | i-edge-cases | 2.6 KB |
| K | k-customer-ux-scorecard | 5.3 KB |

**Commit log:** 11 conventional commit (Sprint 2K HEAD `c68a5a6` üzerinden):

| Hash | Mesaj kısa |
|------|------------|
| `bdfb1ab` | chore(2m-pre): preflight + provider key inventory |
| `af7bbd7` | chore(2m-b): customer install — compose 7/7 healthy + smoke |
| `9adb02c` | test(2m-c): setup wizard 6-step LIVE E2E |
| `a919977` | test(2m-e): first MCP + RAG ingest/query + Türkçe byte-exact |
| `196db88` | test(2m-f): 122 MCP tool kategorize + 22 provider-free deep test |
| `cb1077b` | test(2m-g): cascade 6-down audit — Lesson 11 fail + 200 vs 503 |
| `2ad8d05` | test(2m-h): admin 13/15 + KVKK + data export + audit cap |
| `2f0d291` | test(2m-i): edge cases — UAT-009 + rate limit + Postgres RLS |
| `383f26d` | test(2m-k): UX scorecard 5.7/10 + setup time 3-8dk |
| `3776199` | docs(2m-l): bug log final + 5 founder rec |
| `(M-commit)` | docs(2m-m): closeout + cert Section XI |

**Lesson 12 enforce:** 11/11 commit Co-Authored-By trailer YOK ✅.

---

## 🐛 Bug log summary (26 toplam)

| Öncelik | Sayı | Kritik ID'ler | Müşteri impact |
|---------|------|---------------|----------------|
| **P0** | 4 | 2M-003, 2M-017, 2M-025, 2M-026 | Pilot launch blocker |
| **P1** | 6 | 2M-009, 014, 018, 020, 023, 024 | UX bozar, güvenlik açığı |
| **P2** | 10 | 001, 002, 004, 006, 008, 010, 013, 015, 021, 022 | Polish, sonraki sprint |
| **P3** | 6 | 005, 007, 011, 012, 016, 019 | Note, brief stale çoğu |

**P0 detay:**
1. **2M-003** — Setup wizard HTML `"Ileri"` button 5x (Lesson 11 — ASCII I yerine TR İ).
2. **2M-017** — Cascade 6-down fallback `"Tum saglayicilar gecici hata verdi"` 8 karakter ASCII.
3. **2M-025** — UAT-009 fail-closed BROKEN: backend down → `/admin/*` 200 panel HTML.
4. **2M-026** — Customer compose Postgres yok, Sprint 2K RLS defense-in-depth aktif değil.

**P1 detay:**
- 2M-009 `/panel/*` 404 (canonical `/admin/*`)
- 2M-014 daily_cost IndexError exception
- 2M-018 Cascade HTTP 200 (brief 503 beklentisi)
- 2M-020 Caddyfile `/me/*` route gap
- 2M-023 Image `1.0.0` stale (UAT-038 deletion-status eksik)
- 2M-024 `/auth/login` rate limit YOK (UAT-041)

---

## 🎯 Customer UX scorecard

| Kategori | Puan | Gerekçe |
|----------|------|---------|
| Setup wizard flow | 7/10 | 53s tamamlandı, ama "Ileri" Lesson 11 + grammar |
| Hata mesajları TR | 4/10 | Cascade fallback Türkçe FAIL, stack leak yok pozitif |
| Doc erişimi | 5/10 | `tls internal` + Postgres recipe yok |
| Response kalite | N/A | Provider key SKIP |
| Performance | 9/10 | Setup 53s, MCP p95 315ms, RAG 18ms |
| Türkçe deneyimi | 3/10 | 2 P0 Lesson 11, RAG storage OK ama UI fail |
| Mobil | N/A | Playwright headed skip |
| KVKK/güven | 6/10 | KVKK flow OK, deletion-status 404 + Postgres yok |

**Ortalama (6 kategori):** **5.7/10**

---

## ⚡ Performance metrikleri özet

| Metrik | Gerçek | Hedef | Verdict |
|--------|--------|-------|---------|
| Setup wizard süresi | 53s | <2dk | ✅ EXCELLENT |
| Compose up + setup total | 3-8 dk | ≤30 dk | ✅ EXCELLENT (%10-25) |
| Backend `/healthz` | <50ms | <100ms | ✅ |
| MCP system tools p50 | 2.5ms | <100ms | ✅ |
| MCP system tools p95 | 315ms | <500ms | ✅ |
| RAG ingest | 215ms | <500ms | ✅ |
| RAG query | 18ms | <100ms | ✅ |
| daily_cost tool | IndexError | OK | ❌ P1 |
| rag_status outlier | 423ms | <100ms p95 | ⚠ P2 |

---

## 🇹🇷 Türkçe / kalite / cost özet

**Lesson 11 byte-exact pass rate:**
- RAG storage layer: **8/8 PASS** (100%) ✅
- Setup wizard HTML: **0/5 FAIL** ("Ileri" 5x — P0 2M-003)
- Cascade fallback: **0/8 FAIL** ("Tum saglayicilar gecici" — P0 2M-017)
- Admin/* dashboard title: PASS ("Self-hosted AI ağı" — TR doğru)
- Setup wizard JSON state: lang="en" default ama HTML "tr" inconsistency (P2 2M-006)
- **Net UI critical paths:** ~0% pass

**Çıktı kalitesi:** Provider key olmadan cascade chat live test imkansız. Brief J1 50
prompt Türkçe testi SKIP. RAG storage retrieval Türkçe round-trip GREEN.

**Cost:** Audit ortamında $0 tüketim (provider çağrı yok). Founder paste sonrası
Sprint 2M-Provider-Live ayrı sprint için minimum sample cap $5 öneri korunuyor.

---

## 🏷️ Cert footer status: 🟡 RC

`PRODUCTION_READY_CERTIFICATE_v1.0.0.md` Section XI — Sprint 2M Customer E2E Audit:

> **🟡 RC (Release Candidate)** — 🟢 GREEN damga eligibility **DEĞIL** çünkü:
> - 4 P0 bug açık (2 Türkçe Lesson 11 UI critical paths, 1 fail-closed regression, 1 Postgres RLS customer compose'da aktif değil)
> - Provider live test yapılamadı (FAZ D + F-generation + J skip — founder paste bekler)
> - UI critical paths Türkçe pass rate ~0% (setup HTML + cascade fallback)
> - Sprint 2K defense-in-depth katmanı customer ortamına ulaşmamış (compose Postgres yok)
>
> **Pilot Batch 2 GO/NO-GO:** **NO-GO**
>
> **Cert 🟢 GREEN eligible kriterler (Sprint 2N closure'da):**
> 1. ✅ 0 P0 bug
> 2. ✅ P1 bug ≤ 2
> 3. ✅ Postgres RLS customer compose default
> 4. ✅ Türkçe Lesson 11 CI gate aktif
> 5. ✅ Provider live test (en az 1 sağlayıcı) PASS

---

## 🎯 Founder Recommendations — Top 5 Acil Aksiyon

1. **🚨 Türkçe Lesson 11 blanket-audit + CI gate** (P0 #003 + #017)
   - Setup wizard HTML `"Ileri"` → `"İleri"` 5 yerde
   - Cascade fallback `"Tum saglayicilar..."` → `"Tüm sağlayıcılar..."` byte-exact
   - CI test: assert bytes(msg.encode()) contains `\xc4\xb0` (İ), `\xc4\x9f` (ğ), etc.

2. **🚨 Postgres RLS customer compose'a entegre** (P0 #026)
   - `infra/docker-compose.customer.yml` Postgres 16 service ekle
   - `abs-postgres-data` named volume, Sprint 2K migration boot otomatik
   - Quickstart doc'a Postgres recipe + SQLite legacy fallback opt-in

3. **🚨 UAT-009 fail-closed restore** (P0 #025)
   - Landing `app/admin/layout.tsx` veya `middleware.ts`
   - SSR'da `fetch backend /healthz` → 5xx ise `redirect('/login?backend_down')`
   - CSP `connect-src` revize

4. **🔴 Image `1.0.0` → `1.0.1` retag** (P1 #023)
   - UAT-038 `/v1/me/account/deletion-status` decorator container'a deploy
   - `.github/workflows/image-publish.yml` retag job
   - `.env.example` `ABS_VERSION=1.0.1` default

5. **🔴 `/auth/login` rate limit middleware** (P1 #024)
   - `slowapi` veya `fastapi-limiter` ekle
   - 5 req/min per IP cap, in-memory store yeterli
   - UAT-041 restore

---

## 🛣️ Sprint 2N kararı

**Önerilen:** **Sprint 2N — Hot-fix Patch (1-2 hafta)**

| Aksiyon | Hedef |
|---------|-------|
| 5 founder rec uygula | 4 P0 + 5 P1 fix |
| Cert footer 🟡 → 🟢 | Pilot Batch 2 GO eligibility |
| Provider key paste (founder) | Sprint 2M-Provider-Live ayrı sprint |

**Sonraki adım hiyerarşi:**
1. Sprint 2N hot-fix (acil)
2. Sprint 2M-Provider-Live (founder paste sonrası — FAZ D + F-gen + J tamamlama)
3. Sprint 2L — Postgres RLS dalga 2 (tablo seti genişletme)
4. Pilot Batch 2 GO (gating: 2N closed, 0 P0, cert 🟢 GREEN)

**Pilot 1 (mevcut 3 müşteri):** Sprint 2N hot-fix öncesi durum bilgisi gönderimi
önerilir — "Sprint 2N rolling patch geliyor, Türkçe + güvenlik fix dahil". Pilot 1
müşterilerine refund/credit politikası founder kararı.

---

## 🚦 SPRINT 2M CUSTOMER E2E AUDIT COMPLETE

```
Branch: feat/sprint-2m-customer-e2e-audit
Commits: 11 (Sprint 2K HEAD c68a5a6 üzerinden)
Test ortam: lokal docker compose (M4 /tmp/abs-customer-sim/)
13 FAZ: A-C-E-G-H-I-K-L-M tam koşturuldu, D+F-gen+J SKIP (provider key yok)
Evidence: 11 text dump _agent-tasks/SPRINT_2M_EVIDENCE/ (~24KB)
Bug log: SPRINT_2M_BUG_LOG.md — 4 P0 + 6 P1 + 10 P2 + 6 P3 = 26 toplam
Customer UX scorecard: ortalama 5.7/10 (TR 3/10 düşürür, Perf 9/10 yükseltir)
Setup time: 3-8 dakika (hedef ≤30dk → EXCELLENT %10-25)
Türkçe karakter pass: RAG storage 8/8 ✅ | UI critical paths 0/13 ❌ (2 P0)
Cost: $0 (provider çağrı yok — FAZ D+J skip)
6 provider validate: SKIP (founder paste bekler)
Cascade quality: 6-down graceful SSE ✅ (stack leak yok), HTTP 200 vs 503 P1, TR fallback P0
KVKK 2-step + data export + audit pagination: ✓ (deletion-status image stale)
Cross-tenant RLS: app-level OK, Postgres defense-in-depth aktif değil (P0)
Marka-neutral + Lesson 11/12/13/14/16: enforce ✓ (Lesson 11 storage OK, UI fail)
Cert footer Section XI: 🟡 RC (🟢 GREEN eligible değil)
Closeout: _agent-tasks/SPRINT_2M_CUSTOMER_E2E_AUDIT_REPORT.md
🛑 STOP — Founder bug log review + Sprint 2N hot-fix kararı.
Pilot Batch 2 GO/NO-GO: NO-GO (4 P0 açık).
```

---

**Hazırlayan:** Sprint 2M Worker (autonomous chain)
**Lesson 11/12/13/14/16:** enforce ✓ (RAG layer Türkçe storage PASS, UI critical paths
2 P0 ihlal Sprint 2N hot-fix scope, Co-Authored-By trailer YOK, secret echo YOK,
Hetzner LIVE deploy YOK, marka-neutral)
**Cert footer:** 🟡 RC — Sprint 2N closure'da 🟢 GREEN eligible.
