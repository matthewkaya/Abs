# Worker — Latency Benchmark + PROMISE.md Final Rewrite

> Founder kararı (2026-05-07 00:30): Multi-judge consensus eval terk edildi.
> Kanıt: 4 judge × N=30 run = Cohere/Gemini rate limit email storm + ilk prompt swap_mismatch=3/3 = judges gürültü üretiyor, sinyal yok.
> Yeni yön: **gerçek müşteri deneyimi** ölçülebilen 3 metrik — latency, cost, redundancy.
> Branch: `feat/sprint-q12-deep-quality` (HEAD post-consensus pause)

## 0. Doğrulama disiplini

```
cd core/backend && ./.venv/bin/python -m pytest --no-header -q \
  --ignore=tests/test_providers.py \
  --ignore=tests/test_q03_real_saas_backends.py \
  --ignore=tests/test_update_channel.py
```

Round summary `pytest_full_suite + image_rebuilt_at + live_path_verified` ZORUNLU. Selective subset YASAK. Git commit per round.

## 1. Hedef

PROMISE.md "Quality bar" section'ı **LLM-as-judge tabanlı win-rate iddiasından** kurtaracak. Yerine **empirik 3 metrik** koyacağız — judge gerektirmez, üçüncü taraf API'lara bağımlı değil:

1. **Latency**: Groq GPT-OSS-120B vs Anthropic Claude Sonnet wall-clock ölçüm (P50, P95, mean)
2. **Cost per prompt**: Groq $0 vs Anthropic Sonnet pricing (input+output token × rate)
3. **Provider redundancy**: Cascade order kanıtı — Groq down → Cloudflare → Gemini → Anthropic graceful fallback

Bu 3 metrik **gerçek müşteri deneyimini** yansıtır. "Hangi LLM kazanıyor?" yerine "müşteri ne kazanıyor?" sorusunu cevaplar.

## 2. R1 — Latency benchmark script (ZERO judge, ZERO rate limit risk)

Yeni script `scripts/eval/latency_benchmark.py`:

- Dataset: mevcut `core/backend/tests/fixtures/golden_eval_multimodel.json` (100 prompt) — full kullan, judge yok
- 2 sağlayıcı: Groq `openai/gpt-oss-120b` + Anthropic `claude-sonnet-4-5-20250929`
- Her prompt için wall-clock ölç: `t_start = time.perf_counter()` → call → `t_end - t_start`
- AnthropicThrottle korunuyor (mevcut `multimodel_winrate.AnthropicThrottle` import et)
- **Cohere/Gemini ÇAĞIRMA** — bu run amaçlı dışında, sadece Groq + Anthropic
- Çıktı: `artifacts/promise_verify/latency_benchmark.{md,json}` — P50/P95/mean per provider, ratio (Anthropic/Groq), token-rate

Şema:
```json
{
  "n_prompts": 100,
  "groq": {"p50_ms": 850, "p95_ms": 1400, "mean_ms": 920, "errors": 0},
  "anthropic": {"p50_ms": 4200, "p95_ms": 8500, "mean_ms": 5100, "errors": 0},
  "speedup": {"p50": 4.94, "p95": 6.07, "mean": 5.54},
  "cost_per_prompt_usd": {"groq": 0.0, "anthropic": 0.0042},
  "started_at": "...", "finished_at": "...", "duration_s": ...
}
```

Markdown raporu: tablo + 3 cümle yorumlama.

## 3. R2 — Cost ledger (token × pricing)

`scripts/eval/cost_calculator.py` — basit hesap, eval gerektirmez:

- Anthropic Sonnet 4.5 pricing: $3/Mtok input, $15/Mtok output
- Groq GPT-OSS-120B pricing: $0 (free tier)
- Latency benchmark JSON'undan token count'u oku (response usage'tan)
- 100 prompt × ortalama input/output → aylık 1000 prompt için cost projection

Çıktı: `artifacts/promise_verify/cost_ledger.md`

## 4. R3 — Cascade redundancy proof

Mevcut `core/backend/app/cascade.py` ve `app/providers/` zaten test'le kapsanıyor.
Yeni iş YOK — sadece **kanıt link'le** PROMISE.md'ye:

- `tests/test_cascade*.py` testleri
- `app/cascade.py` cascade order kodu
- LangFuse `cascade.fallback` trace event

Yeni script: `scripts/eval/cascade_smoke.py` — tek prompt × her provider'ı tek tek "down" simulate edip cascade'in next provider'a düştüğünü doğrula. 5 dakikalık run, judge yok, rate limit yok.

Çıktı: `artifacts/promise_verify/cascade_smoke.md`

## 5. R4 — PROMISE.md final rewrite

Mevcut `docs/ABS_HYBRID_TIER_PROMISE.md` "Quality bar" section'ını **TAMAMEN sil**:

- ~v1.2 v1.3'e bump
- "Sprint 13 multi-model ensemble" referansları sil
- 4-judge consensus paragrafı sil
- Founder single-judge measurements paragrafı sil (artık alakasız)
- "≥50% win-rate" lafı zaten yok, kalmasın

Yerine **3 yeni section**:

```markdown
## What we measure (and what we don't)

ABS makes three falsifiable empirical promises:

### 1. Latency — Groq is N× faster than Anthropic on identical prompts
- Evidence: [`artifacts/promise_verify/latency_benchmark.md`](../artifacts/promise_verify/latency_benchmark.md)
- N=100 prompts, paired wall-clock measurement
- Reproduce: `python scripts/eval/latency_benchmark.py`

### 2. Cost — Free path is $0/prompt; Anthropic Plus stays within $20 budget
- Evidence: [`artifacts/promise_verify/cost_ledger.md`](../artifacts/promise_verify/cost_ledger.md)
- Token-counted; quota_monitor enforces 95% hard block
- Reproduce: `python scripts/eval/cost_calculator.py`

### 3. Redundancy — Cascade survives any single-provider outage
- Evidence: [`artifacts/promise_verify/cascade_smoke.md`](../artifacts/promise_verify/cascade_smoke.md)
- 5 providers × kill-each test; cascade falls through every time
- Reproduce: `python scripts/eval/cascade_smoke.py`

## What we do NOT claim

ABS does **not** claim that GPT-OSS-120B is "categorically better" than Claude Sonnet on output quality. We attempted a multi-judge LLM-as-judge consensus eval (4 judges × A/B position swap) and **abandoned it**: cross-judge variance reached 58 percentage points and position-swap mismatch hit 3/3 on the very first prompt. LLM-as-judge produces noise, not signal, on this comparison.

What we observed empirically (legacy single-judge runs, retained as audit trail in `artifacts/promise_verify/`):
- Llama 3.3 70B judge → 80% GPT-OSS win-rate vs Sonnet
- Sonnet 4.5 judge → 22% GPT-OSS win-rate vs Sonnet (judge favoured itself)
- Cross-judge spread = 58pp ⇒ no statistical claim possible

The customer's real win is **cost, latency, and redundancy** — three things we *can* measure with confidence. Output quality is "competitive parity at minimum" by direct usage; founders are encouraged to run their own eyeball N=10 on real tasks before committing.
```

## 6. Round döngüsü

1. R1 = latency_benchmark.py + run + artifact
2. R2 = cost_calculator.py + ledger
3. R3 = cascade_smoke.py + smoke run
4. R4 = PROMISE.md final rewrite + retract win-rate paragraflarını sil
5. R5 = pytest 1806 → ≥1810 (4 yeni test: latency schema, cost calc, cascade smoke, promise structure)
6. R6 = git commit + push (her round atomic)

## 7. KRİTİK Yasaklar

- **Cohere/Gemini ÇAĞIRMA** — son 5 saatte rate limit email aldık, soğuma süresinde ekstra çağrı YASAK
- **Multi-judge consensus eval'i RESURRECT etme** — methodology terk edildi
- "≥50% win-rate" iddiası geri ekleme
- LLM-as-judge harness'ları çalıştırma (artifacts'taki eski sonuçlar audit trail olarak kalsın, yenisi koşma)
- Selective subset → FULL CLEAN sayma
- Image rebuild her backend round

## 8. Delegation %70+ MCP

- Latency script: `mcp__abs__ask_gptoss` (httpx + asyncio paralel)
- Cost calculator: `mcp__abs__ask_gptoss` (token math)
- Cascade smoke: `mcp__abs__ask_kimi`
- PROMISE.md rewrite: `mcp__abs__ask_qwen32b` (TR/EN, sade dürüst dil)
- Schema test'leri: `mcp__abs__write_tests`

## 9. Başarı kriteri

- 3 yeni script ship + 3 artifact (latency, cost, cascade)
- PROMISE.md "Quality bar" section silinmiş, yerine "What we measure / What we do NOT claim" eklenmiş
- pytest 1806 → ≥1810
- Image rebuild + git commit per round
- HİÇBİR Cohere veya Gemini API call yapılmamış (önemli — rate limit cooldown)

## 10. Devam komutu

```
cd /Users/eneseserkan/Main/abs-server-product
git checkout feat/sprint-q12-deep-quality
git log --oneline -5
cat _agent-tasks/WORKER_LATENCY_REWRITE.md
ls scripts/eval/
cat docs/ABS_HYBRID_TIER_PROMISE.md | head -60
```

Engelleyici YOK. Bu round vaat dokümanını **ölçülebilir 3 empirik metriğe** oturtuyor — judge'sız, rate-limit-safe, müşteri deneyimini gerçekten yansıtan. Founder ile sabahki review'a hazır olacak.
