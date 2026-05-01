# Task 007 — Hooks (5 Hook Modülü Port + Hibrit Mod)

## Bağlam

005'te MCP shell + 10 tool, 006'da 13 pipeline + 16 tool tamam. Şu an müşteri Claude Code bağlanıp ABS tool'larını çağırabiliyor.

Bu task **hook sistemini** ekler — Claude Code'un her aksiyonunu (Bash, Edit, Write, MCP call) intercept ederek:
- Quality nudge'lar verir ("bu uzun python3 -c yerine `ask gptoss` kullan")
- Plan-first uyarıları ("3+ aksiyon, plan.md yok")
- RAG inject (yeni dosya yazılırken benzer pattern enjekte)
- Content enrichment (büyük markdown gönderildiğinde quality gate)
- Feature nudge (kullanılmayan MCP tool önerisi)

SERVER'da bu 5 modül günde 100+ kez tetikleniyor — **ABS'nin "akıllı kalan" kısmı**.

**Bağlı docs:**
- `docs/architecture.md` § 2 (hook bileşenleri)
- `docs/operations.md` § 6 (4-katmanlı garanti — hook'lar kalitenin bir parçası)
- SERVER `~/.claude/hooks/hook_modules/*.py` (5 modül, 1124 satır toplam)

## Hibrit Çalışma Modu (Kritik Tasarım Kararı)

Hook'lar **iki şekilde** tetiklenebilir:

### Mod A: Claude Code Native Hook (önerilen — müşteri Claude Code kullanıyorsa)
- Müşteri makinesinde `~/.claude/hooks/` altında shell script + Python module
- Claude Code her tool call öncesi bunu çalıştırır
- ABS install scripti **opsiyonel olarak** bunu kurar
- Avantaj: Claude Code'un native hook altyapısı, performans iyi

### Mod B: MCP Middleware (default — Claude Code yoksa veya istemiyorsa)
- ABS backend'inde `app/mcp/middleware.py` her MCP tool call'ı yakalar
- Hook fonksiyonlarını çağırır (tool call öncesi)
- Avantaj: Müşterinin Claude Code config'ine dokunmaz, izole

**Bu task ikisini de kurar.** Müşteri install sırasında seçer (`abs.install --hooks=native|middleware`).

## Kaynaklar (SERVER Read-only)

```
/Users/eneseserkan/.claude/hooks/hook_modules/feature_nudge.py    (413 satır)
/Users/eneseserkan/.claude/hooks/hook_modules/delegate_nudge.py   (133 satır)
/Users/eneseserkan/.claude/hooks/hook_modules/plan_first.py       (72 satır)
/Users/eneseserkan/.claude/hooks/hook_modules/rag_inject.py       (208 satır)
/Users/eneseserkan/.claude/hooks/hook_modules/enrichment.py       (298 satır)

/Users/eneseserkan/.claude/hooks/guard_logic.py                   (517 satır — main dispatcher)
/Users/eneseserkan/.claude/hooks/pre-tool-guard.sh                (12 satır — bash wrapper)
/Users/eneseserkan/.claude/hooks/rag_helpers.py                   (RAG cache+rate)
```

## Beklenen Çıktı

### 1. Hook Modülleri (`core/backend/app/hooks/`)

- [ ] `app/hooks/__init__.py` — paket
- [ ] `app/hooks/feature_nudge.py` — port + adaptasyon (413 satır → ~400 ürün)
  - 15 Bash pattern + 8 MCP idle nudge
  - Rate limit `/tmp/abs_feature_nudge_rate.json` → `settings.cache_dir/feature_nudge_rate.json`
  - Tüm hardcoded `/tmp/abs_*` path'leri config'ten
- [ ] `app/hooks/delegate_nudge.py` — port (133 satır)
  - Inline python3 -c analiz tespit
  - Curl + python3 pipe
  - Büyük docs Write nudge
  - Rate limit dosyası adaptasyon
- [ ] `app/hooks/plan_first.py` — port (72 satır)
  - 3+ aksiyon + plan.md yok uyarısı
  - Artifact dizini referansı (üründe `settings.artifacts_dir`)
- [ ] `app/hooks/rag_inject.py` — port (208 satır)
  - GUARD 6: Bash/Edit öncesi RAG context fetch
  - GUARD 10: Write öncesi benzer pattern fetch
  - Cache + rate limit
  - **Not:** Gerçek RAG entegrasyonu 009-rag'de gelecek; bu task'ta stub (in-memory mock)
- [ ] `app/hooks/enrichment.py` — port (298 satır)
  - md/json/html/py/ts content enrichment
  - Quality gate (6 katman)
  - A/B test logic
  - Provider call (qual_code pipeline'ı kullanır — 006'dan)

- [ ] `app/hooks/dispatcher.py` — guard_logic.py'nin ürün versiyonu
  - 13 GUARD'ı çağır (sıralı: freeze, investigate, content-router, RAG, plan-first, feature-nudge, delegate-nudge)
  - JSON I/O Claude Code spec uyumlu (PreToolUse hook output formatı)
- [ ] `app/hooks/common.py` — ortak helper'lar (`deny()`, `_log_hook_error`, `ALWAYS_ALLOW_FILES`)

### 2. MCP Middleware (Mod B)

- [ ] `app/mcp/middleware.py` güncelle — her tool call öncesi:
  - `dispatcher.run(tool_name, tool_input)` çağır
  - Hook bir `additionalContext` döndürürse → response'a ekle (Claude'a görünür)
  - Hook `deny` ederse → tool call iptal, error response
- [ ] `app/mcp/server.py` — middleware register

### 3. Native Hook Install Script (Mod A — opsiyonel)

- [ ] `infra/install_native_hooks.sh`:
  ```bash
  #!/usr/bin/env bash
  # Claude Code'a ABS hook'larını kur
  # ~/.claude/hooks/ altına symlink + pre-tool-guard.sh
  # Kullanıcı opt-in (install.sh içinde sorulur veya manual)
  ```
- [ ] `core/native-hooks/` — Claude Code'a kopyalanacak shell + Python wrapper'lar
  - `pre-tool-guard.sh` — bash wrapper, ABS backend'e HTTP POST yapar (`http://localhost:8443/v1/hooks/dispatch`)
  - `dispatch_to_abs.py` — Python helper (request → response → stdout)
- [ ] Backend endpoint: `app/api/hooks.py` — `POST /v1/hooks/dispatch` (Claude Code hook output spec)

### 4. Konfigürasyon

- [ ] `app/config.py` güncelle:
  - `cache_dir: str = "/app/data/cache"` (hook rate limit, cache dosyaları)
  - `artifacts_dir: str = "/app/data/artifacts"` (plan-first için)
  - `hooks_enabled: bool = True`
  - `hooks_mode: str = "middleware"` ("middleware" | "native" | "both")
- [ ] `infra/.env.example` güncelle

### 5. Test

- [ ] `tests/test_hooks_feature_nudge.py`:
  - 5 critical pattern (qual-code, race, RAG, fullstack, code_review nudge'ları)
  - Rate limit testi
- [ ] `tests/test_hooks_delegate_nudge.py`:
  - inline python3 -c → DELEGATE nudge
  - Big docs Write → DELEGATE nudge
- [ ] `tests/test_hooks_plan_first.py`:
  - 3+ aksiyon + no plan.md → uyarı
- [ ] `tests/test_hooks_rag_inject.py`:
  - Code file write → mock RAG context inject
- [ ] `tests/test_hooks_enrichment.py`:
  - Big md write → quality gate trigger (mock provider)
- [ ] `tests/test_hooks_dispatcher.py`:
  - 13 GUARD sırası
  - Freeze mode
  - Hook error log isolation (bir hook çökse diğerleri devam)
- [ ] `tests/test_mcp_middleware_with_hooks.py`:
  - MCP tool call → middleware tetikler → hook nudge ek metin döner

## Kısıtlar

- ❌ SERVER'a Write/Edit yasak
- ❌ Feature Parity Kuralı: 5 hook'un hepsi zorunlu, 1124 satır toplam korunmalı
- ❌ Hardcoded `/Users/eneseserkan/...` path'leri → config'ten
- ❌ Hardcoded `/tmp/abs_*` → `settings.cache_dir`
- ✅ Hook fail-safe: bir hook hata atarsa Claude Code akışı kesintisiz devam (silent fail + log)
- ✅ MCP middleware async (FastAPI lifespan ile uyumlu)
- ✅ Test her hook için minimum 2 senaryo

## Delegation Yönergesi

Bugün TPD reset (006 raporundan biliyoruz). Delegation bol kullanılabilir.

### 1. SERVER hook'larını chunk-read

```
Read ~/.claude/hooks/hook_modules/feature_nudge.py
Read ~/.claude/hooks/hook_modules/delegate_nudge.py
Read ~/.claude/hooks/hook_modules/plan_first.py
Read ~/.claude/hooks/hook_modules/rag_inject.py offset=0 limit=120
Read ~/.claude/hooks/hook_modules/rag_inject.py offset=120 limit=120
Read ~/.claude/hooks/hook_modules/enrichment.py offset=0 limit=150
Read ~/.claude/hooks/hook_modules/enrichment.py offset=150 limit=150
Read ~/.claude/hooks/guard_logic.py offset=0 limit=200
```

### 2. RAG için pattern

```
mcp__abs__rag_query "claude code pretooluse hook json output additional context"
mcp__abs__rag_query "fastapi middleware async tool call interceptor"
```

### 3. Hook port — `qual_code` her hook için (5 ayrı çağrı, kısa)

```
mcp__abs__qual_code
  prompt: "feature_nudge.py'yi ürün için adapte et:
  [SERVER kodu, ~410 satır]
  Değişiklikler:
  - /tmp/abs_*.json → settings.cache_dir / 'feature_nudge_rate.json'
  - import os/json ortak modül helper'a taşı
  - rate limit logic değişmeyecek
  - 15 Bash pattern + 8 MCP idle nudge aynı
  Test imports için top-level absolute path."
```

### 4. Dispatcher (`fullstack be`)

```
mcp__abs__fullstack
  layer: "be"
  prompt: "13 GUARD dispatcher Python (FastAPI uyumlu):
  - guard order: freeze, investigate, content-enrich, RAG, plan-first, feature-nudge, delegate-nudge
  - Each guard: try/except → silent fail + log
  - Output Claude Code PreToolUse hook spec uyumlu (additionalContext, permissionDecision, updatedInput)
  - JSON I/O"
```

### 5. MCP middleware

```
mcp__abs__qual_code
  prompt: "FastMCP middleware async hook integration:
  - Her tool call öncesi dispatcher.run(tool_name, tool_input)
  - Hook nudge text varsa → tool response'a ekle
  - Hook deny ederse → tool call iptal + error
  - asyncio uyumlu"
```

### 6. Test (toplu)

```
mcp__abs__qual_code
  prompt: "pytest 7 hook test grubu:
  - feature_nudge: 5 pattern + rate limit
  - delegate_nudge: inline python + big docs
  - plan_first: aksiyon sayacı
  - rag_inject: mock RAG response
  - enrichment: quality gate (mock provider)
  - dispatcher: GUARD sırası + freeze + isolation
  - middleware: MCP integration
  Mock asyncio + tempfile cache_dir."
```

### 7. Final review

```
mcp__abs__code_review tier="standard"
mcp__abs__judge_patch
```

### Hedef Delegation

- **Min %35 delegation** (TPD reset, scope büyük)
- MCP çağrı **min 10 kez**

## Adımlar (sıra önemli)

1. SERVER 5 hook + guard_logic + rag_helpers chunk read
2. `rag_query` ile FastMCP middleware pattern
3. `app/hooks/common.py` — ortak helper (`deny`, `_log_hook_error`, `ALWAYS_ALLOW_FILES`, `ALLOWED_AGENT_TYPES`)
4. `app/hooks/feature_nudge.py` (`qual_code` delege)
5. `app/hooks/delegate_nudge.py` (`qual_code` delege)
6. `app/hooks/plan_first.py` (`qual_code` delege)
7. `app/hooks/rag_inject.py` — STUB version (gerçek RAG 009'da; mock random pattern dön)
8. `app/hooks/enrichment.py` — quality gate ve provider call qual_code pipeline'ı kullansın (006'dan)
9. `app/hooks/dispatcher.py` — 13 GUARD orchestrator (`fullstack be` delege)
10. `app/mcp/middleware.py` — hook integration (`qual_code` delege)
11. `app/api/hooks.py` — `/v1/hooks/dispatch` endpoint (Mod A için)
12. `infra/install_native_hooks.sh` + `core/native-hooks/*.sh` (Mod A için)
13. `app/config.py` + `.env.example` — yeni env'ler
14. Test (`qual_code` delege)
15. Docker rebuild + Claude Code manuel test:
    - `mcp__abs__ask_gptoss` çağrısı → middleware tetikler → response'da feature_nudge text görünür mü
    - Bash command "ask compare React vs Vue" → delegate_nudge tetiklenir mi (Mod A native test)
16. `code_review` + `judge_patch`
17. Summary

## Doğrulama

```bash
cd core/backend
.venv/bin/pytest tests/ -q
# Beklenen: 58 önceki + min 14 yeni = 72+ passed

cd ../../infra
docker compose build backend
docker compose up -d

# Mod B test (default — middleware)
curl -k -b cookies.txt https://abs.local/api/hooks/test \
  -d '{"tool":"Bash","input":{"command":"python3 -c \"data=[1,2]; analyze(data)\""}}' \
  -H "Content-Type: application/json"
# Beklenen: 200, additionalContext içinde "DELEGATE NUDGE" geçer

# Claude Code MCP integration test
claude
> mcp__abs__ask_gptoss prompt="kod yaz: fonksiyon"
# Beklenen: Tool çalışır + response'da "FEATURE NUDGE: qual-code kullanabilirsin" gibi nudge

# Mod A test (native hook — opsiyonel)
bash infra/install_native_hooks.sh  # symlink kur
echo '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"x=1\""}}' | \
  bash ~/.claude/hooks/pre-tool-guard.sh
# Beklenen: Backend'e HTTP POST, response stdout'a basılır
```

## Tamamlama

1. `git diff --stat`
2. `judge_patch` skor
3. `completed/007-hooks-summary.md`:
   ```markdown
   ## Ne Yapıldı
   - 5 hook modülü port (1124 satır SERVER → X satır ürün)
   - Dispatcher: 13 GUARD orchestrator
   - MCP middleware integration
   - Native hook install script (Mod A opsiyonel)
   - 14 yeni test (toplam 72+)

   ## Hook Modülleri Detay
   - feature_nudge: 15 Bash + 8 MCP nudge
   - delegate_nudge: inline python + curl pipe + big docs
   - plan_first: 3+ aksiyon uyarısı
   - rag_inject: STUB (009 RAG implementation bekliyor)
   - enrichment: 6-katman quality gate

   ## İki Mod Doğrulama
   - Mod A (native): install script + symlink test
   - Mod B (middleware): MCP tool call → nudge ek metin

   ## Delegation
   [detay]

   ## STUB'lar (gelecek task)
   - rag_inject: gerçek RAG 009-rag'de bağlanacak
   - enrichment provider: 006'daki qual_code pipeline kullanılıyor (TPD problem'i de etkileyebilir)
   ```
4. Task'ı `completed/`'e taşı
5. "007 tamam" rapor

---

**Tahmini süre:** 4-5 saat
**Sonraki task:** `008-mcp-tools-batch.md` — Kalan 65+ MCP tool batch port (judge_patch, write_tests, write_docs, ask_smart, ask_disagree, ask_reasoner, code_review, fullstack, vs.)
