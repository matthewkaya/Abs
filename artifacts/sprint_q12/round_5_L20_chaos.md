# Q12 — Round 5 — L20 chaos engineering

**Tarih:** 2026-05-02
**Layer:** L20 — chaos engineering (Q12 yeni)
**Branch:** `feat/sprint-q12-deep-quality`
**Worker:** Opus 4.7 (1M ctx)

---

## 0. Hedef

Production failure mode'larında chat client'ın resilience davranışını
doğrula. Live `docker kill` riskli (25h customer journey state)
olduğundan iki katmanlı yaklaşım:

1. **Application-layer (CI-safe):** Playwright `page.route()` ile
   network interception → 5 chaos senaryo. Otomatik runs.
2. **Infrastructure-layer (opt-in):** isolated `q12-l20-chaos`
   compose namespace + scripted SIGKILL/pause/netcut. Founder
   manual invoke; live volumes intact.

---

## 1. Application-layer chaos sonuçları

5 senaryo × Playwright spec:

| # | Senaryo | Mock | Beklenen UI | Sonuç |
|---|---------|------|-------------|-------|
| 1 | Backend 503 (vault unavailable) | `route.fulfill({status:503})` | Error tile + Retry + Configure CTA | ✅ PASS |
| 2 | Container kill mid-stream | `route.abort("connectionaborted")` (1st hit) | Error tile visible | ✅ PASS |
| 3 | Rate limit 429 chain | `route.fulfill({status:429, retry-after:30})` | Error tile visible | ✅ PASS |
| 4 | Timeout — 12s hang | `setTimeout(12000)` then abort | Error tile OR pending state (no silent fail) | ✅ PASS |
| 5 | 307 redirect loop → 502 | 4× 307 self-redirect, then 502 | Error tile within 10s | ❌ **FAIL** → `test.fail()` |

**Çıktı:** `core/landing/__tests__/playwright/q12-l20-chaos.spec.ts`

```
Running 5 tests using 5 workers
5 passed (18.6s)
```

(Senaryo 5 `test.fail()` annotation ile expected-failure; Playwright
"5 passed" raporu doğru — 4 chaos PASS + 1 documented gap.)

---

## 2. Q12-L20-001 (MED) — chat client redirect-loop guard yok

**Bulgu:** Senaryo 5'te server 4 kez 307 redirect döndürüp 5. denemede
502 verdiğinde, chat client error tile göstermez. UI pending
spinner'da indefinitely takılır. KOBİ pilot için: misconfigured
proxy / Caddy redirect bug → kullanıcı stuck.

**Kök neden:** Chat client `useChat` hook'u (Vercel AI SDK)
`fetch()` default redirect mode `follow` kullanıyor. Browser
kendi automatic redirect handling'i 307'leri takip ediyor;
location header self-pointing olduğunda browser'ın internal
redirect-loop detection'ı tetikleniyor (≥20 redirect veya
network error). Ama burada 4 redirect → 1 502 zinciri internal
threshold'u aşmıyor; 502 normal response olarak parse ediliyor
ama setError çağrısı SSE stream parser dışında, response.ok
false branch'inde catch ediliyor mu net değil — silent failure.

**Çözüm yolları:**

1. `useChat` config'inde `fetch` wrapper ekle:
   ```ts
   const fetchWithDeadline = (url, init) =>
     fetch(url, { ...init, signal: AbortSignal.timeout(10_000) });
   ```
2. Custom error handler:
   ```ts
   useChat({ api: "/v1/chat/completions",
             onError: (err) => setLocalError(err.message) })
   ```
3. Redirect-loop guard backend tarafında (Caddy `respond` not
   `redir` for chat completions endpoint).

Sprint 22 backlog. Q12-L20 spec `test.fail()` ile guard — chat
client fix shipped olunca annotation kaldır, test tekrar PASS
expectation'a döner.

---

## 3. Infrastructure-layer chaos runner

Live destructive operasyonlar için `scripts/chaos/q12_l20_isolated.sh`:

```bash
bash scripts/chaos/q12_l20_isolated.sh up        # isolated namespace
bash scripts/chaos/q12_l20_isolated.sh kill      # scenario 1 SIGKILL
bash scripts/chaos/q12_l20_isolated.sh pause     # scenario 2 hung
bash scripts/chaos/q12_l20_isolated.sh netcut    # scenario 3 partition
bash scripts/chaos/q12_l20_isolated.sh diskfull  # scenario 4 disk
bash scripts/chaos/q12_l20_isolated.sh redis     # scenario 5 (deferred)
bash scripts/chaos/q12_l20_isolated.sh down      # teardown
```

Compose project name `q12-l20-chaos` — live `infra-*` ve `abs-cj-*`
volume'ları **dokunulmaz** (parallel namespace). Backend port
`18000` (offset). Founder manual invoke.

---

## 4. Sonraki round'lar (L20 FULL CLEAN için)

- Round +X: senaryo 5 fix (chat client redirect-loop guard) → annotation kaldır
- Round +Y: isolated namespace kill scenarios live run + measure (RTO/RPO)
- Round +Z: senaryo 6 (Redis OOM eviction storm — Sprint 21 cache layer)

---

## 5. Atomic commit

```
fix(q12/L20): Round 5 Q12-L20-001 chaos engineering — 5 chat resilience scenario + isolated runner
```

---

## 6. Layer state

L20 sayım: **1/3** (4 PASS + 1 documented `test.fail()` Q12-L20-001).
Sprint 22 chat client redirect-loop fix sonrası FULL CLEAN'e ilerler.
