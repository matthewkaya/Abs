# Q12 — Round 10 — L20 sweep 3 (chat redirect-loop guard production fix)

**Tarih:** 2026-05-02
**Layer:** L20 — chaos engineering 3rd sweep
**Branch:** `feat/sprint-q12-deep-quality`
**Worker:** Opus 4.7 (1M ctx)

---

## 0. Hedef

Round 5'te 5 chaos senaryo + 1 documented `test.fail()` annotation
shipped. Q12-L20-001 (MED): chat client 307 redirect chain'inde
error tile göstermez — UI pending spinner indefinitely. Sprint 22
backlog'undan **ileri çekildi** (production fix çok küçük).

---

## 1. Root cause

`core/landing/lib/chat-stream.ts:215` `useChat.send()` fetch çağrısı
default `redirect: "follow"` kullanıyor. Browser 307'leri otomatik
takip ediyor. Misconfigured Caddy `redir` rule chat completions
endpoint'inde 307 zinciri döndürdüğünde:

- Browser fetch promise pending kalır (her 307 yeni request)
- Final 502 sonunda gelir — ama UI'da pending spinner halen
- `setError` hiç çağrılmaz çünkü `res.ok` kontrolü 502'ye geç
  vardığında çoğu kullanıcı zaten sayfayı bırakmış olur

---

## 2. Fix

```diff
+ // Q12-L20-001 — chat completions is a POST + SSE; the backend never
+ // legitimately returns a 3xx, so `redirect: "error"` makes a
+ // misconfigured proxy (e.g. Caddy redir loop) surface as a fetch
+ // rejection rather than silently following until the browser's
+ // hard 20-redirect ceiling. Combined with the existing AbortController
+ // for user-initiated cancel, this keeps the UI honest under failure.
  try {
    const res = await fetch("/v1/chat/completions", {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({...}),
+     redirect: "error",
      signal: controller.signal,
    });
```

`redirect: "error"` browser'ın ilk 3xx response'unda fetch rejection
fırlatmasını sağlar → existing catch block → `setError(msg)` →
error tile visible.

Tek satır production fix.

---

## 3. Test refit

```diff
- // Q12-L20-001 (MED) — chat client does not surface an error tile when
- // the upstream returns a 307 redirect loop ending in a 5xx. The UI
- // remains in pending state indefinitely. `test.fail()` annotation
- // documents the known regression; remove it once the chat client gains
- // a max-redirect / abort-on-loop guard.
+ // Q12-L20-001 — Round 10 fix: `redirect: "error"` on the SSE fetch
+ // makes the chat client surface 307 immediately as an error tile,
+ // instead of silently following the redirect chain until the
+ // browser's hard 20-redirect ceiling.
  test("scenario 5: 307 redirect loop — does not hang the UI", async ({ page }) => {
-   test.fail(true, "Q12-L20-001 chat client lacks redirect-loop guard (Sprint 22 backlog)");
    if (!(await ensureAuthed(page))) test.skip(true, "abs_session cookie missing");
```

---

## 4. Sonuç

```
Running 5 tests using 5 workers
5 passed (18.7s)
```

Senaryo 5 artık **gerçek PASS**, `test.fail()` kaldırıldı.

Q10/Q11 regression sweep:
```
q10-no-api-degradation + q11-l11-cross-browser + q11-l12-responsive:
22 passed (60 skipped viewport-bound)
```

---

## 5. Build çıkarımı (yan bulgu)

Round 10 sırasında `npm run build` sonrası `next start -p 3458`
çalıştırınca tüm route'lar 500 ENOENT verdi:

```
ENOENT: '/Users/eneseserkan/Main/abs-server-product/core/landing/.next/required-server-files.json'
```

**Root cause:** `next.config.ts:70` `output: "standalone"` set.
`next start` ile uyumsuz — `node .next/standalone/server.js`
şart. Ama clean build sonrası `.next/standalone/` oluşmuyor
(possible: outputFileTracingRoot anomaly, Next 15.5.x).

**Çözüm (Round 10 scope):** dev mode (`next dev --port 3457`)
ile chaos test çalıştırıldı. Production deploy için Docker
multi-stage build kullanılıyor (T-Q06) — orada doğru entry
point. Local dev için sıkıntı yok.

**Sprint 22 backlog (Q12-L20-002 LOW):**
- `npm run start:standalone` script ekle: `node .next/standalone/server.js`
- veya local prod test için `output: "standalone"` env-gated yap

---

## 6. Layer state

L20 sayım: **3/3 FULL CLEAN ⭐**
(Round 5 ship + Round 6 rerun + Round 10 fix + scenario 5 PASS)

| Layer | Counter | Notes |
|-------|---------|-------|
| **L17** | **3/3 ⭐** | bundle break-even validator + unit + CI gate |
| **L18** | **3/3 ⭐** | cold-cache + CDP throttle 12/12 PASS |
| **L19** | **3/3 ⭐** | backwards compat 11/11 PASS |
| **L20** | **3/3 ⭐** | chaos 5/5 PASS (redirect-loop guard fix) |
| L21 | 0/3 | founder-gated |

**4/5 Q12 yeni layer FULL CLEAN.** Sadece L21 (founder approval)
kaldı.

---

## 7. Atomic commit

```
fix(q12/L20): Round 10 chat client redirect-loop guard — redirect:"error" → 5/5 chaos PASS L20 FULL CLEAN
```
