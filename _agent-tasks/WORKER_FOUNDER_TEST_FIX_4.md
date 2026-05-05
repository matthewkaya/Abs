# Founder Tester Session — Fix Round 4 (Phase A-E sonrası)

> **Tetikleyici (2026-05-05):** Founder Playwright Round 3 verify (cost savings ✅) sonrası 5 fonksiyonel test phase çalıştırdı:
> - Phase A workflow execute ✅ (synth+dry-run+enqueue+durable 1s done)
> - Phase B chat multi-turn 🐞 HIGH BUG
> - Phase C magic-link signup ✅
> - Phase D marketplace install + sandbox ✅ + 🐞 MED BUG
> - Phase E meeting transcription ✅ (WhisperX + diarization + summary)
>
> **Branch:** `feat/sprint-q12-deep-quality` (HEAD 3dbf996, baseline 1781 PASS / 0 / 0)

---

## 0. ⚠️ DOĞRULAMA DİSİPLİNİ (S5+S10+S11+S12 + R1+R2+R3 ders)

```bash
cd core/backend && ./.venv/bin/python -m pytest --no-header -q \
  --ignore=tests/test_providers.py \
  --ignore=tests/test_q03_real_saas_backends.py \
  --ignore=tests/test_update_channel.py
```

Round summary'ye `pytest_full_suite: <X> / 0 fail / 0 error` + `image_rebuilt_at: <ts>` + `live_path_verified: true` ZORUNLU.

**Selective subset YASAK.** Git commit ZORUNLU (Round 2 dersi).

---

## 1. BUG-9 HIGH — `chat.py:_run_cascade()` hala stub (R2'de KAÇIRILDI)

**Founder evidence:** Phase B 3 turn chat → 3 stub response:
```
"Cascade canli uclari henuz aktif degil.Yapılandırılmadı"
```
sessions=11, history persist ✅, ama her assistant message bu stub'ı içeriyor. Customer chat sayfası işe yaramayacak.

**Root cause:** `core/backend/app/api/chat.py:134-157`:

```python
async def _run_cascade(prompt: str, max_tokens: int = 1024) -> CascadeResponse:
    """Bypass the FastAPI route's auth dependency and call the cascade
    directly..."""
    fallback_chain: List[str] = []
    cascade_req = CascadeRequest(prompt=prompt, max_tokens=max_tokens)

    mock_result = await _try_mock(cascade_req, fallback_chain)
    if mock_result is not None:
        return mock_result

    active = get_active_providers()
    if not active:
        raise HTTPException(503, detail="no_providers_configured")

    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=f"live_cascade_pending: {','.join(active)}",  # ← STUB
    )
```

Round 2'de `/v1/cascade/run` endpoint stub'ı kaldırıldı + `call_with_cascade()` orchestrator wire'landı. Ama `chat.py:_run_cascade()` ayrı bir helper fonksiyon — DOKUNULMADI. Chat stream path bu helper'ı çağırıyor → stub raise → chat.py:387 stub error message yakalıyor → SSE'ye yazıyor.

**Fix:**
```python
# core/backend/app/api/chat.py
from app.cascade.orchestrator import call_with_cascade
from app.providers.schemas import ProviderError

async def _run_cascade(
    prompt: str,
    max_tokens: int = 1024,
    skip_paid_providers: bool = False,
) -> CascadeResponse:
    """Bypass the FastAPI route's auth dependency and call cascade via
    the live orchestrator."""
    fallback_chain: List[str] = []
    cascade_req = CascadeRequest(prompt=prompt, max_tokens=max_tokens)

    mock_result = await _try_mock(cascade_req, fallback_chain)
    if mock_result is not None:
        return mock_result

    active = get_active_providers(skip_paid=skip_paid_providers)
    if not active:
        raise HTTPException(
            503,
            detail="no_free_providers_configured" if skip_paid_providers
                   else "no_providers_configured"
        )

    primary, *rest = active
    try:
        resp = await call_with_cascade(
            prompt,
            primary=primary,
            fallbacks=tuple(rest),
            max_tokens=max_tokens,
        )
    except ProviderError as exc:
        raise HTTPException(502, f"all_providers_failed: {exc.detail}")

    return CascadeResponse(
        completion=resp.text,
        provider=resp.provider,
        fallback_chain=[primary] + list(rest),
        tokens_used=resp.tokens,
        cached=resp.cached,
        elapsed_ms=resp.latency_ms,
        model=resp.model,
    )
```

**Verify (founder Playwright):**
```bash
# Login + send chat message via UI
# Expect: assistant response is REAL LLM content (not stub)
# /v1/chat/sessions/{sid}/messages → assistant message has provider field set
```

**Test:**
```python
# tests/test_chat_cascade_wiring.py
def test_chat_completion_uses_live_cascade(client_admin):
    """Phase B founder evidence — chat path was stubbed, R2 wired only /v1/cascade/run."""
    r = client_admin.post("/v1/chat/sessions", json={"first_user_message": "Türkiye başkenti?"})
    sid = r.json()["session_id"]
    r2 = client_admin.post(
        f"/v1/chat/sessions/{sid}/completions",
        json={"messages": [{"role": "user", "content": "Türkiye başkenti?"}]},
    )
    # Read SSE stream
    text = r2.text  # or stream
    assert "Cascade canli uclari henuz aktif degil" not in text
    assert "live_cascade_pending" not in text
    assert "Ankara" in text or "Istanbul" in text or len(text) > 50
```

---

## 2. BUG-10 MED — `/v1/marketplace/installed` tenant scoping

**Founder evidence:** Phase D
- `POST /v1/marketplace/install {plugin_id:"slack-receiver", tenant:"demo-acme"}` → 201 ✅ (sandbox container created)
- `GET /v1/marketplace/installed` → `{"tenant":"default", "installed":[]}` ❌ (tenant ≠ admin's tenant + boş list)

Beklenen: list endpoint admin'in cookie session tenant'ını okumalı, `tenant=demo-acme` döndürmeli + 1 installed plugin.

**Hipotez:** Cookie session → tenant resolve adımında default'a fallback. `current_admin` dependency `tenant` field'ını çıkarmıyor olabilir.

**Surface:** `core/backend/app/api/marketplace.py:367` `@router.get("/installed")`.

**Fix:**
- `current_admin` dependency'den tenant_slug çek
- Veya `Depends(current_tenant)` ile multi-tenant resolver ekle
- List endpoint `WHERE tenant_slug = :resolved` filtre

**Test:**
```python
def test_marketplace_installed_scoped_to_admin_tenant(client_admin_demo_acme):
    """Phase D founder evidence — installed list returned tenant=default, empty."""
    client.post("/v1/marketplace/install", json={"plugin_id": "slack-receiver", "tenant": "demo-acme"})
    r = client.get("/v1/marketplace/installed")
    body = r.json()
    assert body["tenant"] == "demo-acme"
    assert any(p["plugin_id"] == "slack-receiver" for p in body["installed"])
```

---

## 3. BUG-11 LOW — Page title double "Automatia ABS · Automatia ABS"

**Founder evidence:** Phase B-E hepsi:
```
title="Sohbet — ABS Panel · Automatia ABS · Automatia ABS"
title="Toplantılar — ABS Panel · Automatia ABS · Automatia ABS"
title="Plugin Marketplace — ABS Admin · Automatia ABS · Automatia ABS"
```

Root: Round 1 SWEEP'te 13 sayfa metadata.title eklendi ama root layout `title.template = "%s · Automatia ABS"` zaten suffix ekliyor. Sublayout'lar kendi metinlerinde "ABS Panel" / "ABS Admin" + ekstra "Automatia ABS" yazmış.

**Fix:** Sublayout `metadata.title` artık sadece sayfa adı + section ("Sohbet — ABS Panel") OLMALI; root template "%s · Automatia ABS" suffix'i tek başına ekler.

**Mevcut (yanlış):**
```tsx
// core/landing/app/panel/chat/layout.tsx
export const metadata = { title: "Sohbet — ABS Panel · Automatia ABS" };
```

**Düzgün:**
```tsx
export const metadata = { title: "Sohbet — ABS Panel" };
```

13 layout/page dosyası güncellenir.

---

## 4. BONUS — Setup wizard env name uyumu (founder yapmıştı)

`infra/.env` örneğinde:
- `ABS_CLOUDFLARE_API_TOKEN` (yanlış — pydantic prefix ABS_, field cf_api_token → ABS_CF_API_TOKEN)
- `ABS_CLOUDFLARE_ACCOUNT_ID` (yanlış)

Founder local'de fixledi. Worker `.env.example` ve setup wizard üretilen env çıktısına da yansıtmalı (CUSTOMER deploy hazırlığı için):

```bash
# .env.example
ABS_CF_API_TOKEN=<your_cloudflare_api_token>
ABS_CF_ACCOUNT_ID=<your_cloudflare_account_id>
```

Setup wizard form input name'leri (`name="cf_account_id"`, `name="cf_api_token"`) doğru zaten.

---

## 5. ROUND DÖNGÜSÜ

1. R1 = BUG-9 chat._run_cascade live wiring
2. R2 = BUG-10 marketplace tenant scoping
3. R3 = BUG-11 title sweep refactor (sub-layout sadece sayfa ad + section)
4. R4 = .env.example Cloudflare ABS_CF_* uyumu
5. Full pytest GREEN (1781 → ≥1784, 3 yeni test)
6. Founder Playwright Phase A-E re-run (final big test)

---

## 6. KESİN YASAK

- Selective subset rapor → FULL CLEAN sayma
- Image rebuild gate her backend round
- "Functionally works" ≠ "git committed"
- L21 + Mutmut + DR actual: founder approval yok
- Pilot/market/outreach gündem dışı

---

## 7. DELEGATION (%70+ MCP)

- Cascade orchestrator wiring: `mcp__abs__ask_gptoss`
- Multi-tenant scope pattern: `mcp__abs__ask_kimi`
- Next.js metadata.title hierarchy: `mcp__abs__ask_kimi`
- Patch judge: `mcp__abs__judge_patch`
- Test pattern: `mcp__abs__write_tests`

---

## 8. BAŞARI KRİTERİ

- BUG-9 chat live (founder Playwright Phase B 3 turn → 3 real LLM response)
- BUG-10 `/v1/marketplace/installed` tenant=demo-acme + plugin görünür
- BUG-11 title `Sohbet — ABS Panel · Automatia ABS` (tek "Automatia ABS")
- .env.example ABS_CF_* uyumlu
- Backend pytest 1781 → ≥1784
- Image rebuild + live curl evidence

---

## 9. ROUND BAŞLANGIÇ

### Round 1 = BUG-9 chat._run_cascade
Replace stub with `call_with_cascade()` orchestrator. Phase B regression test (3 turn → 3 LLM response).

### Round 2 = BUG-10 marketplace installed tenant scoping
`current_admin` dependency tenant resolve + filter.

### Round 3 = BUG-11 title sub-layout sadeleştirme
13 layout/page dosyası `metadata.title` sade (root template suffix yeter).

### Round 4 = .env.example Cloudflare uyumu

### Final = Founder Playwright Phase A-E re-run

---

## 10. EVIDENCE

- `/tmp/founder_phase_a.json` (workflow execute PASS)
- `/tmp/founder_phase_b.json` (chat stub bug)
- `/tmp/founder_phase_c.json` (magic-link signup)
- `/tmp/founder_phase_d.json` (marketplace tenant bug)
- `/tmp/founder_phase_e.json` (transcription PASS)
- Screenshots: `/Users/eneseserkan/Desktop/Digisfer Inc/phase[A-E]_*.png`
- Backend log: chat.py:387 "Cascade canli uclari henuz aktif degil" stub branch hit per turn

---

## 11. DEVAM KOMUTU

```bash
cd /Users/eneseserkan/Main/abs-server-product
git checkout feat/sprint-q12-deep-quality
git log --oneline -5
cat _agent-tasks/WORKER_FOUNDER_TEST_FIX_4.md
cat /tmp/founder_phase_b.log | grep "Cascade canli"
```

Round 1 = BUG-9 chat live wiring'den başla. Engelleyici YOK.

**Bu round sonrası founder TÜM Phase A-E'yi tek "büyük final test" olarak yeniden çalıştıracak — tester teslimat eşik son MÜHÜR.**
