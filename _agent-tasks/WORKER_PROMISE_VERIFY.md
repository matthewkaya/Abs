# Worker — Promise Verify (5 fix + 1 evidence run)

> Founder audit (2026-05-06): `docs/ABS_HYBRID_TIER_PROMISE.md` 11 vaatten 5 canlı, 6 eksik/yarım. Tester paketi gönderilmeden önce 5 fix + Sprint 13 win-rate eval gerçek run zorunlu.
> Branch: `feat/sprint-q12-deep-quality` (HEAD post-Round-6, baseline 1791 PASS / 0 / 0)

## 0. Doğrulama disiplini

```
cd core/backend && ./.venv/bin/python -m pytest --no-header -q \
  --ignore=tests/test_providers.py \
  --ignore=tests/test_q03_real_saas_backends.py \
  --ignore=tests/test_update_channel.py
```

Round summary: `pytest_full_suite + image_rebuilt_at + live_path_verified` zorunlu. Selective subset YASAK (S5+S10+S11+S12 ders). Git commit per round.

## 1. BUG-V1 HIGH — `/admin/usage` widget yok

**Vaat (PROMISE.md):** "real-time `Free path: X %` + `Claude budget: Y %`"

**Gerçek:** `core/landing/app/admin/` listesinde `usage` page YOK.

**Fix:**
- Backend endpoint `/v1/admin/usage`: free_path_pct + claude_budget_pct + last_24h_provider_mix döndür. Veri kaynağı: `quota_monitor.py` (claude_used) + `cost_log.jsonl` (free path counts).
- Frontend `core/landing/app/admin/usage/page.tsx` + `layout.tsx` (metadata.title="Kullanım — ABS Admin"). Metric tile'ları (Tremor) + 7-gün trend chart.
- Sidebar entry `/admin/usage` — workflow-builder altına "Kullanım".

**Test:**
- pytest: `/v1/admin/usage` 200, schema validate
- Playwright: `/admin/usage` h1 görünür + 2 metric tile + chart container

## 2. BUG-V2 HIGH — Workflow USD cost estimate yok

**Vaat:** "`Estimated cost per run: $X.XX` shows zero for free-tier-only workflows"

**Gerçek:** `app/api/workflows.py` execute response `estimate_s` (saniye) döndürüyor, USD yok.

**Fix:**
- `runner.estimate_cost(plan_steps)` ekle: her node tipi (`abs_tool`, `llm`, `http`, `hitl`) için unit cost dict (free=$0, claude_haiku=$0.0001/call, claude_sonnet=$0.0005/call vb.). Provider key'in opt-in durumuna göre çoğaltma.
- ExecuteResponse'a `estimated_cost_usd: float = 0.0` field ekle.
- Tüm node free-tier ise total = 0, sadece anthropic node varsa hesapla.

**Test:**
- 4-node free-tier workflow → `estimated_cost_usd == 0.0`
- 1-node anthropic enabled workflow → `estimated_cost_usd > 0`

## 3. BUG-V3 MED — Opt-in flip audit emit yok

**Vaat:** "every opt-in flip and quota-block event written to T-016 SOC2 audit log"

**Gerçek:** `ABS_ANTHROPIC_ENABLED` env değişikliği audit emit etmiyor. Quota-block emit ediyor mu doğrulanmadı.

**Fix:**
- Settings change detection: backend startup'ta önceki state ile karşılaştır (`/app/data/last_optin_state.json`), değişiklik varsa `emit_event(action="settings.optin.flip", outcome="changed", reason="anthropic_enabled=true|false")`.
- `QuotaExceeded` raise edildiğinde `emit_event(action="quota.block", outcome="enforced", reason="claude budget 95% reached")`.

**Test:**
- Toggle ABS_ANTHROPIC_ENABLED → audit row `settings.optin.flip` emerge
- Force quota 95% → audit row `quota.block`

## 4. BUG-V4 HIGH — Sprint 13 win-rate kanıtsız

**Vaat:** "Sprint 13 multi-model ensemble (T-049..T-056) verified that GPT-OSS-120B baseline answers reach ≥50 % win-rate against Claude Opus on the golden eval set."

**Gerçek:** `golden_eval_dataset.json` SADECE RAG retrieval testi (T-015), multi-model dataset değil. Sprint 13 sonuç dosyası YOK. Vaat **kanıtsız claim**.

**Fix (gerçek run):**
- `tests/fixtures/golden_eval_multimodel.json` ship: 30 prompt × 3 task tipi (kod, analiz, çeviri). Beklenen output sketch'leri.
- Eval script `scripts/eval/multimodel_winrate.py`: her prompt için GPT-OSS-120B + Claude Opus paralel çağır, judge_patch (LLM-as-judge) skor.
- Hesap: GPT-OSS win = 1, Opus win = 0, tie = 0.5. Toplam ≥%50 hedef.
- Sonuç `artifacts/promise_verify/sprint_13_winrate.md` — actual %, ilk 5 fail örneği, win/loss/tie breakdown.

**Test:**
- Eval dataset 30+ row, schema valid
- Win-rate ≥ 0.50 (gerçek değer rapor edilir, claim'e uymuyorsa **PROMISE.md güncelle**)

## 5. BUG-V5 MED — LangFuse `claude_tokens_used_pct_month` wired mı?

**Vaat:** LangFuse dashboard `claude_tokens_used_pct_month` time-series.

**Gerçek:** `app/observability/langfuse_*.py` var ama bu specific metric'in emission noktası belirsiz.

**Fix:**
- `quota_monitor.py` `record_usage()` çağrılırken LangFuse'a `langfuse.score(name="claude_tokens_used_pct_month", value=used_pct, trace_id=...)` push et.
- Test: 1 Anthropic call sonrası LangFuse trace içinde score görünür.

## 5b. BUG-V6 HIGH — Plus tier context limit empirik test

**Founder soru (2026-05-06):** "$20 Plus üyelik API key'iyle context limit doldurmadan ilerleyebilecek mi?"

**Test scenario:**
- Müşteri Plus key (~5h sliding 50 msg quota) ABS_ANTHROPIC_API_KEY olarak girer
- ABS cascade default skip_paid_providers=true → Anthropic'e gitmez
- 50 ardışık prompt çalıştır (script): hepsi Groq/Gemini/Cerebras → Plus quota TÜKENMEMELİ
- Sonra skip_paid=false ile 5 prompt → Plus quota hesabı görünmeli, 95% threshold öncesi durmalı

**Script ship:** `scripts/eval/plus_tier_context_test.py` — 50 prompt batch + quota_monitor before/after diff + sonuç raporu `artifacts/promise_verify/plus_tier_context.md`.

**Beklenen sonuç:** skip_paid=true × 50 prompt → Plus quota delta = 0. skip_paid=false × 5 → delta görünür ama 95% altında.

## 5c. BUG-V7 HIGH — Max-tier kalite parity ölçümü

**Founder soru:** "Max plan kalitesi sunabilecek mi?"

**Test scenario:**
- 30 prompt × 3 task tipi (kod, analiz, TR yazım)
- Versiyon A: Anthropic Sonnet 4.6 direct (Max tier proxy — Opus pahalı, Sonnet ucretsiz close approximation)
- Versiyon B: ABS cascade qual_* pipeline (race + judge + humanizer)
- LLM-as-judge (Claude Opus blind eval): hangisi daha kaliteli? winA / winB / tie

**Script ship:** `scripts/eval/max_tier_parity.py` — 30 prompt × 2 versiyon × judge_patch + Opus blind judge. Sonuç `artifacts/promise_verify/max_tier_parity.md` — Versiyon B (ABS cascade) ≥%50 win + tie hedef. Değilse vaat **gerçek değil**, PROMISE.md güncelle.

## 5d. BUG-V8 MED — MCP tool çağrılabilirlik (Plus + Free tier)

**Founder soru:** "MCP tool'ları doğru kullanabilecek mi?"

**Test scenario:**
- mcp__abs__* tool'ları (50+) **backend'e bağlı**, müşterinin Anthropic tier'ından bağımsız.
- Test: Plus key ile Claude Code session simulate, 10 farklı MCP tool çağır:
  - ask_gptoss, ask_kimi, ask_qwen32b, ask_gemini, ask_cohere
  - race_code, qual_code, judge_patch, fullstack_scan, rag_query
- Her biri 200 OK + valid response + 0 error.

**Script ship:** `scripts/eval/mcp_tool_smoke.py` — 10 tool × test prompt → success matrix. Sonuç `artifacts/promise_verify/mcp_tool_smoke.md`.

**Beklenen:** 10/10 PASS, Plus key Anthropic-bound değil; MCP tool'lar Anthropic call yapanlar (örn. judge_patch LLM tarafı) skip_paid=true varsayılan.

## 6. Round döngüsü

1. R1 = BUG-V1 /admin/usage widget
2. R2 = BUG-V2 workflow USD estimate
3. R3 = BUG-V3 audit opt-in flip + quota block
4. R4 = BUG-V4 Sprint 13 win-rate eval gerçek run
5. R5 = BUG-V5 LangFuse metric verify
6. R6 = BUG-V6 Plus tier context limit empirik test
7. R7 = BUG-V7 Max-tier kalite parity ölçümü
8. R8 = BUG-V8 MCP tool smoke (Plus + Free)
9. R9 = PROMISE.md güncelle (3 yeni vaat eklenir: context koruma, Max parity, MCP cross-tier; gerçek ölçüm sonuçlarına göre iddia)

Her round atomic commit. Pytest 1791 → ≥1797 (5 yeni test). Image rebuild backend dokunulduğunda.

## 7. Yasaklar

- Selective subset rapor → FULL CLEAN sayma
- Image rebuild gate her backend round
- Win-rate iddia EDİLMESIN, gerçek değer ÖLÇÜLSÜN — claim'e uymazsa PROMISE.md güncellenir (founder dürüstlük tercihi)
- Pilot/market/outreach gündem dışı

## 8. Delegation %70+ MCP

- Endpoint kod: ask_gptoss
- Frontend chart: ask_kimi (React/Tremor patterns)
- Eval script: ask_gptoss + write_tests
- Audit emit: code_review tier=standard
- PROMISE.md güncelleme: ask_qwen32b

## 9. Başarı kriteri

- 5 vaat madde live (curl + Playwright kanıt)
- Sprint 13 win-rate gerçek sayı (≥%50 ise vaat doğrulandı, değilse PROMISE.md revize)
- **Plus tier context test** — 50 free prompt sonrası quota delta=0 kanıt
- **Max-tier parity** — gerçek win/tie oranı (≥%50 hedef, değilse PROMISE.md update)
- **MCP tool smoke** — 10/10 PASS Plus key ile
- pytest 1791 → ≥1800 (8 yeni test)
- Image rebuild + git commit per round
- Founder Playwright Phase B-D-E + 5 yeni assertion regression test

## 10. Devam komutu

```
cd /Users/eneseserkan/Main/abs-server-product
git checkout feat/sprint-q12-deep-quality
git log --oneline -5
cat _agent-tasks/WORKER_PROMISE_VERIFY.md
cat docs/ABS_HYBRID_TIER_PROMISE.md
ls core/landing/app/admin/
grep -nE "WARN_PCT_DEFAULT|BLOCK_PCT_DEFAULT|QuotaExceeded" core/backend/app/observability/quota_monitor.py
```

Engelleyici YOK. Bu round vaat dokümanı ile gerçek implementation'ı eşitliyor — tester paketi gönderilmeden önce son production-readiness gap'leri.
