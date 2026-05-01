# Task 030 — 029 Caveat Fix + Compound Integration + Provider Catalog Refresh

**Status:** READY (Worker autonomous mode — first of 3-task chain 030→031→032)
**Tahmini süre:** 3-4 saat
**Bağımlı task'lar:** 023 (i18n), 029 (compliance, caveat'lar), 010+026 (provider/MCP tool altyapı)

## ⚠️ DELEGATION KRİTİK
029'da `delegated to gptoss/qwen32b, ~25k tokens saved` ile başardın — devam et:
- Locale TR/ES çevirileri → ZORUNLU `ask "..." qwen32b`
- Markdown 2000+ char → `ask "..." gptoss`
- 5000+ char hook BLOCK eder zaten

## 0. Bağlam — 029 Caveat'ları + Yeni Fırsat

029 sonu raporda 3 caveat:
1. **Purge script invocable but not yet scheduled in production cron** — daily systemd timer ekle
2. **Privacy page non-GDPR sections Turkish-only** — landing/app/privacy/page.tsx EN/TR/ES tam locale
3. **Legal docs templates pending counsel review** — README'de zaten not var, "DRAFT — lawyer review required" header banner ekle

Yeni fırsat (SERVER tarafından gelen keşifler):
4. **Groq compound + compound-mini** agentic models test edildi, ABS'ye MCP tool olarak eklenmeli
5. **Cerebras qwen-3-235b-a22b-instruct-2507** üst-tier (test edildi: 419 char yanıt)
6. **Gemini-flash-latest / gemini-pro-latest** auto-upgrade alias (3.x'e geçince otomatik)
7. **News scrape pattern** — gece pipeline'daki gemini-search 5-sorgu pattern, ABS'ye MCP tool

---

## 1. Amaç (DoD)

- [ ] **Purge script systemd timer** — `infra/systemd/abs-purge-deleted-accounts.{service,timer}` daily 03:00
- [ ] **Privacy page i18n** — `core/landing/app/privacy/page.tsx` EN default + TR + ES (3 locale full)
- [ ] **Legal docs DRAFT banner** — `docs/legal/{dpa-template,subprocessors,...}.md` üstüne uniform `> ⚠️ DRAFT — Legal review required before signing` banner
- [ ] **`ask_compound` MCP tool** — Groq compound (multi-step agentic, max_tokens=2000)
- [ ] **`ask_compound_mini` MCP tool** — compound-mini (hızlı agentic)
- [ ] **`ask_cerebras_qwen` MCP tool** — Cerebras qwen-3-235b-a22b
- [ ] **`ask_gemini_latest` + `ask_gemini_pro_latest`** — auto-upgrade alias'lar
- [ ] **`news_digest` MCP tool** — 5 paralel gemini-search sorgu (Anthropic/OpenAI/Gemini/GitHub/MCP) → markdown digest
- [ ] **Provider catalog config** — `app/cascade/provider_catalog.json` 6 yeni model entry
- [ ] **Tool inventory smoke** (`infra/scripts/mcp_tool_smoke.py` 024) yenilenir 6 yeni tool ile
- [ ] 30+ yeni test, pytest 550 → ~580
- [ ] vitest 30 → 33 (privacy page i18n test 3 dil)
- [ ] Tool count 113 → 119 (+6: compound, compound_mini, cerebras_qwen, gemini_latest, gemini_pro_latest, news_digest)
- [ ] 6 smoke evidence

---

## 2. Modüller

### Modul A — Purge Script Systemd Timer
**Yeni:** `infra/systemd/abs-purge-deleted-accounts.service`
```ini
[Unit]
Description=ABS daily account purge (GDPR right-to-erasure)
After=network.target

[Service]
Type=oneshot
WorkingDirectory=/app
ExecStart=/usr/bin/python3 /app/infra/scripts/purge_deleted_accounts.py --json-log /var/log/abs-purge.jsonl
StandardOutput=journal
StandardError=journal
```

`infra/systemd/abs-purge-deleted-accounts.timer`:
```ini
[Unit]
Description=Daily run of ABS account purge

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

`docs/billing-runbook.md` patch — Section "Account Purge Schedule" ekle.

3 test (`test_purge_systemd_units.py`): unit dosya syntax, timer schedule parse, executable path correct.

### Modul B — Privacy Page i18n Tam
**Patch:** `core/landing/app/privacy/page.tsx` + `core/landing/locales/{en,tr,es}.json`

Mevcut Turkish-only sections (data collection, cookies, contact, vb.) için:
- EN locale key'lerini ekle (mevcut 023 i18n keylerine devam)
- TR locale (mevcut metinleri taşı)
- ES locale (delegate `ask "Privacy policy section translate to Spanish: ..." qwen32b`)
- `[lang]/privacy/page.tsx` route Next.js i18n routing

3 vitest (`__tests__/Privacy.i18n.test.tsx`): EN render, TR switch, ES switch.

### Modul C — Legal Docs DRAFT Banner
**Patch:** Üstüne uniform banner (4 dosya):
- `docs/legal/dpa-template.md`
- `docs/legal/subprocessors.md`
- `docs/data-retention-policy.md`
- `docs/legal/privacy-policy.md` (varsa)

Banner:
```markdown
> ⚠️ **DRAFT — LEGAL REVIEW REQUIRED**
> This document is a template provided as-is. Before signing with customers,
> qualified legal counsel review is mandatory. Automatia BCN takes no liability
> for unreviewed use. See `docs/legal/README.md` for review checklist.
```

Yeni: `docs/legal/README.md` (~400 kelime EN, delegate gptoss): "Legal Review Checklist for ABS Templates"

2 test (`test_legal_docs_banner.py`): banner her dosyada var, README mevcut.

### Modul D — Compound MCP Tools
**Yeni:** `core/backend/app/mcp/tools/compound_tools.py`:
```python
async def ask_compound(prompt: str, max_tokens: int = 2000) -> str:
    """Groq Compound — multi-step tool-calling agentic. Karmaşık problem (planning + tool kullanım)."""
    return await _ask_groq_via_provider(prompt, "groq/compound", max_tokens)

async def ask_compound_mini(prompt: str, max_tokens: int = 1000) -> str:
    """Groq Compound Mini — hızlı agentic. Kısa multi-step (matematik, planlama)."""
    return await _ask_groq_via_provider(prompt, "groq/compound-mini", max_tokens)
```

Provider integration: `app/providers/groq.py` patch — compound modelleri whitelist.

5 test (`test_compound_tools.py`): mock httpx, response parse, max_tokens default, error handling, registry check.

### Modul E — Cerebras qwen-235b + Gemini Latest Alias MCP Tools
**Yeni:** `core/backend/app/mcp/tools/upper_tier_tools.py`:
```python
async def ask_cerebras_qwen(prompt: str, max_tokens: int = 2000) -> str:
    """Cerebras Qwen3-235B — üst tier (paid/free dikkat)."""
async def ask_gemini_latest(prompt: str) -> str:
    """Gemini Flash Latest — auto-upgrade (3.x otomatik)."""
async def ask_gemini_pro_latest(prompt: str) -> str:
    """Gemini Pro Latest — auto-upgrade pro tier."""
```

5 test (`test_upper_tier_tools.py`): mock provider call, alias resolution, fallback when key missing.

### Modul F — News Digest MCP Tool
**Yeni:** `app/mcp/tools/news_digest.py`:
- 5 paralel `ask_gemini_search` sorgu: Anthropic / OpenAI / Gemini / GitHub trending / MCP news
- Output markdown digest (her sorgu için section)
- Cache 1h (`/tmp/abs_news_digest_cache.json`)

4 test (`test_news_digest.py`): mock parallel calls, cache hit, markdown format, error tolerance (1-2 query fail OK).

### Modul G — Provider Catalog Config
**Yeni:** `core/backend/app/cascade/provider_catalog.json`
```json
{
  "version": "2026-04-27",
  "providers": [
    {"id": "groq-compound", "model": "groq/compound", "tier": "agentic", "context": 131072, "free_quota": 14400, "added": "2026-04-27"},
    {"id": "groq-compound-mini", "model": "groq/compound-mini", "tier": "agentic", "context": 131072, "free_quota": 14400, "added": "2026-04-27"},
    {"id": "cerebras-qwen-235b", "model": "qwen-3-235b-a22b-instruct-2507", "tier": "upper", "context": 32768, "added": "2026-04-27"},
    {"id": "gemini-flash-latest", "model": "gemini-flash-latest", "tier": "auto-upgrade", "context": 1048576, "free_quota": 1500, "added": "2026-04-27"},
    {"id": "gemini-pro-latest", "model": "gemini-pro-latest", "tier": "auto-upgrade", "context": 1048576, "free_quota": 1500, "added": "2026-04-27"}
  ]
}
```

`docs/api-reference.md` regen (gen_api_reference.py 020) → 6 yeni tool göster.

3 test (`test_provider_catalog.py`): JSON load, tier values valid, version present.

### Modul H — Tool Smoke Refresh
**Patch:** `infra/scripts/mcp_tool_smoke.py` (024) — 6 yeni tool için test fixture (mock httpx).

1 test: smoke script tüm 119 tool için ok+skip+fail rapor üretir, fail=0.

---

## 3. Test Stratejisi (30+ test)

| Modül | Test |
|---|:-:|
| A purge systemd | 3 |
| B privacy i18n (frontend) | 3 vitest |
| C legal banner | 2 |
| D compound tools | 5 |
| E upper-tier tools | 5 |
| F news_digest | 4 |
| G provider catalog | 3 |
| H smoke refresh | 1 |
| Tool count guard | 1 update |
| **TOPLAM** | **27 backend + 3 frontend = 30** |

Backend: 550 → **577**. Frontend: 30 → **33**. Tool: 113 → **119** (+6).

---

## 4. Smoke Evidence (`/tmp/abs-030-smoke/evidence/`)

1. `01_purge_systemd_units.json` — service+timer dosya doğrulama
2. `02_privacy_i18n_3lang.json` — EN/TR/ES render snapshots
3. `03_legal_banner_check.json` — 4 doc banner var doğrulama
4. `04_compound_mcp_call.json` — mock compound çağrısı
5. `05_provider_catalog.json` — 6 yeni provider entry
6. `06_news_digest_sample.json` — 5 query parallel + markdown output

---

## 5. Adım Adım

```
1. baseline pytest 550 + tool 113
2. Modul A: purge systemd timer + 3 test
3. Modul B: privacy i18n 3-lang (delegate ES → qwen32b) + 3 vitest
4. Modul C: legal banner 4 doc + README (gptoss EN ~400w) + 2 test
5. Modul D: compound MCP tools + 5 test
6. Modul E: upper-tier tools + 5 test
7. Modul F: news_digest + 4 test
8. Modul G: provider_catalog + 3 test
9. Modul H: smoke refresh + 1 test
10. Tool count 113 → 119 doğrula
11. 6 smoke evidence
12. summary + completed/
13. memory snapshot 030
```

## 6. DoD

```
[ ] 8 modül A-H tamam
[ ] pytest 577 (+27)
[ ] vitest 33 (+3 privacy i18n)
[ ] tool 119 (+6)
[ ] 6 smoke evidence
[ ] regression sıfır
[ ] summary + completed/
[ ] memory snapshot 030
```

## 7. Notlar

1. **Compound tier "agentic"** — cascade router'da yeni kategori (existing: code, tr, classify, fast, etc.). Worker `app/cascade/router.py` patch ile compound'a route etsin "multi-step task" detection.
2. **Cerebras tier check** — paid plan'a sahip olmayan müşteri için graceful fallback (Cerebras 401/403 → cascade'de skip).
3. **Privacy ES çeviri** — qwen32b kullan (EN→ES), back-translate ile doğrula (qual_translate pattern).
4. **News digest cache** — 1h TTL, gece pipeline'daki pattern'i benzer.
5. **Memory snapshot:** task sonu `session_resume_state_20260427_030.md`.
