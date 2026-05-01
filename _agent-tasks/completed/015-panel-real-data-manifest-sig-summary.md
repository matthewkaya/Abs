# Task 015 — Panel Real Data + Manifest Signature + Watchdog Deploy Doc (SUMMARY)

**Tamamlandı:** 2026-04-25
**Süre:** ~1.5 saat (planlanan 3-4h altında)
**Sonuç:** 7 modül + Registry + lifespan etki yok (existing). Hepsi yeşil.

## Özet

| Hedef | Önce | Sonra | Δ |
|-------|------|-------|---|
| pytest yeşil | 223 + 2 skip | **247 passed + 2 skipped** | +24 |
| MCP tool sayısı | 96 | **99** (`daily_cost`, `learnings_recent`, `learnings_log`) | +3 |
| Mevcut testler | yeşil | **yeşil** (regresyon yok) | korundu |
| `_build_budget.today_usd` | random 0.80-4.20 | **gerçek tracker × pricing** | yeni |
| `_build_budget.learnings_count` | random 440-480 | **gerçek `recent_count(30)`** | yeni |
| `cache_stats` MCP tool | counter integration zaten | live cascade hot-path bağlı | doğrulandı |
| Manifest fetch | plaintext | **RS256 fail-closed verify** | yeni |
| Watchdog deploy | yok | `deploy.sh` + `docs/operations.md` § 11+12 | yeni |

## ⚠️ Manifest Private Key Durumu

Worker `infra/scripts/generate_manifest_keys.sh` çalıştırdı:
- **Private key (`/tmp/abs-015-manifest-keys/private.pem`)** — REDACTED. **Repo'ya commit YOK**, `.gitignore` `manifest-keys/` ekler. Kullanıcı `/tmp/abs-015-manifest-keys/private.pem` dosyasını **1Password / hardware token / encrypted offsite**'a taşımalı, sonra `/tmp/`'tan silmeli.
- **Public key (`app/update/manifest_pubkey.pem`)** — repo'ya gömüldü, müşteri verify için kullanır. `.gitignore` `*.pem` exception ile bu dosya korunur.

```
$ test -f app/update/manifest_pubkey.pem && echo "pubkey OK"
pubkey OK
$ test ! -f app/update/manifest_private.pem && echo "private NOT in repo"
private NOT in repo
```

## Modul A — Cascade Cache Integration

Cascade orchestrator `call_with_cascade()` zaten 011/012'de cache get/set kullanıyordu. 015'te hot path doğrulandı: `default_cache.get(key)` cache miss/hit counter'ı artırır → `cache_stats` MCP tool gerçek değer döner.

**Yeni test:** `tests/test_cache_integration.py` (5 test) → **5/5 PASS** (4 zorunlu + 1 ek cascade integration)
- `cache_miss_first_call`, `cache_hit_second_call`, `cache_different_prompts`, `cache_ttl_expiry`, `cascade_uses_cache_on_repeat_call` (real provider mock)

## Modul B — Daily Cost Estimator

**Yeni dosya:** `app/billing/cost_estimator.py` (~80 satır)
- `_build_alias_index()` — `provider_configs` YAML'larından `ask_<alias>` + `ask_<id-normalized>` → (provider, alias, model) build
- `estimate_daily_cost()` — `tracker.snapshot()` × pricing × tokens → today_usd, projected_monthly_usd, by_provider, breakdown (top 10)
- Token sayısı tahmini: 1500 avg/call, 30/70 input/output split (note: 016+ gerçek token tracking)

**Patch:** `app/api/stream.py::_build_budget` — `today_usd`/`projected_monthly_usd` random kalktı, `estimate_daily_cost()` çağrılır.

**Yeni test:** `tests/test_cost_estimator.py` (5 test) → **5/5 PASS** (4 zorunlu + 1 note assert)
- empty tracker → 0.0
- ask_claude-haiku 100 calls → > 0, breakdown[0] anthropic
- ask_foobar_unknown 5000 calls → 0.0 (provider_configs'ta yok)
- claude-opus vs gemini-flash-lite → claude-opus ilk sırada (sorted by cost)

## Modul C — Learnings JSONL Store

**Yeni dosya:** `app/learnings/store.py` (~95 satır)
- `log(category, lesson, source?, project?)` — 6 valid kategori (bugfix/delegation/arch/security/perf/ux), 24h dedup (sha256 hash), 500-char trim
- `recent(limit=20)` — son N JSONL satırı parse
- `recent_count(window_days=30)` — cutoff filter
- `stats()` — total + by_category + last_30d/7d
- Path: `data_dir/learnings.jsonl`

**Patch:** `app/api/stream.py::_build_budget` — `learnings_count = recent_count(30)` (random 440-480 kalktı)

**Yeni test:** `tests/test_learnings_store.py` (6 test) → **6/6 PASS** (4 zorunlu + 2 ek empty/stats)
- `log_creates_jsonl_entry`, `log_idempotent_within_24h`, `recent_count_window_days`, `invalid_category_rejected`, `empty_lesson_rejected`, `stats_reports_by_category`

## Modul D — Manifest RS256 Signature

**Yeni dosyalar:**
- `app/update/signature.py` (~70 satır) — `verify_manifest(bytes, sig_b64)` PKCS1v15+SHA256 RSA, `fetch_signature(url)` `.sig` URL'den base64 cek. Fail-closed: pubkey yok / cryptography yok → False.
- `app/update/manifest_pubkey.pem` — RSA-4096 public key (worker `generate_manifest_keys.sh` ile generate etti, public.pem repo'ya kopyalandı)
- `infra/scripts/generate_manifest_keys.sh` (~35 satır, executable) — RSA-4096 keypair generate, kullanıcıya next-step talimatı

**Patch:**
- `app/update/manifest.py::fetch_manifest` — cache miss path'inde `update_signature_required=True` ise `fetch_signature` + `verify_manifest`. Sig yok → `error: signature missing — refused`. Verify fail → `error: signature invalid`. Cache TTL içinde tekrar verify YOK.
- `app/config.py` — `update_signature_required: bool = True` (production default)
- `.gitignore` — `manifest-keys/` ignore + `!core/backend/app/update/manifest_pubkey.pem` exception

**Yeni test:** `tests/test_manifest_signature.py` (5 test) → **5/5 PASS** (4 zorunlu + 1 ek dev mode skip)
- `verify_returns_false_when_no_pubkey` — pubkey path missing → False (fail-closed)
- `verify_with_valid_signature` — tmp keypair openssl sign + verify → True
- `verify_with_tampered_manifest` — sign(A) + verify(B) → False (sabotaj)
- `fetch_manifest_rejects_unsigned_when_required` — sig 404 + required=True → state="unknown", error contains "signature"
- `fetch_manifest_skips_verify_when_disabled` — required=False → manifest dön, error yok (dev mode)

**Regression:** `tests/test_update_channel.py` 6 test fixture'ına `update_signature_required=False` eklendi (signature mock yok, dev path).

## Modul E — Watchdog Deploy Doc + Script

**Yeni dosya:** `infra/watchdog/deploy.sh` (~55 satır, executable)
- Hetzner CX11 / DO smallest VPS otomatik kurulum
- `watchdog` system user, Python venv + httpx/pyyaml install
- `/etc/cron.d/abs-watchdog` (06:00 UTC daily)
- `/etc/logrotate.d/abs-watchdog` (weekly rotate)
- Discord webhook env

**Patch:** `docs/operations.md` — 2 yeni bölüm:
- **§ 11 Watchdog Deploy (Hetzner)** — VPS spec (€4/ay), DNS, kurulum adımları, Discord webhook setup
- **§ 12 Manifest Release Flow** — manifest.json hazırlama, openssl sign + base64, S3 upload, master key sahipliği

**Patch:** `infra/watchdog/README.md` — `deploy.sh` referansı + manifest signing flow

**Test:** YOK (deploy.sh + doc, runtime test edilmez)

## Modul F — 3 MCP Tools + 99 Guard

**Yeni dosya:** `app/mcp/tools/billing_tools.py` (~50 satır, 3 tool)
- `daily_cost` — `estimate_daily_cost()` JSON
- `learnings_recent(limit=20)` — `recent + stats` JSON
- `learnings_log(category, lesson, project?)` — `log()` → `{ok, hash}` JSON

**Patch:** `app/mcp/server.py` (tam Write override) — `billing_tools` import + count
**Patch:** `tests/test_tools_count.py` — 96 → **99 guard**, must_have'a 3 tool

**Test:** 2/2 PASS. `_REGISTERED_COUNT == 99`.

## Modul G — Panel Real Data Tests

**Yeni test:** `tests/test_panel_real_data_v2.py` (3 test) → **3/3 PASS**
- `build_budget_uses_real_cost` — `estimate_daily_cost` mock → today_usd 1.23 panel'de görünür
- `build_budget_uses_real_learnings` — `recent_count` mock → learnings_count 7
- `cache_stats_returns_real_counter` — fresh cache + 2 miss + 1 hit → hits=1 misses=2 hit_rate_pct=33.3

## Test Sonuçları

```
.venv/bin/pytest -q
247 passed, 2 skipped in 6.56s
```

**Önce:** 223 + 2 skip. **Sonra:** 247 + 2 skip. **Hedef:** 245+. **+24 yeni test:**
- test_cache_integration.py: 5
- test_cost_estimator.py: 5
- test_learnings_store.py: 6
- test_manifest_signature.py: 5
- test_panel_real_data_v2.py: 3

**+2 SKIP** 013'ten korundu (sops binary).

**Mevcut testler korundu:**
- test_update_channel.py 6/6 (signature_required=False fixture eklendi)
- test_panel_banner.py 3/3, test_stream_real_data.py 2/2
- test_cascade.py 7/7
- test_setup_wizard.py 7/7
- ... toplam 247

## Live MCP Smoke (Kanıtlar `/tmp/abs-015-smoke/evidence/`)

uvicorn `--port 8770` (env: `ABS_UPDATE_SIGNATURE_REQUIRED=false` dev mode).

### 1. `daily_cost` (MCP) — boş tracker → 0.0 USD
```json
{
  "today_usd": 0.0,
  "projected_monthly_usd": 0.0,
  "by_provider": {},
  "breakdown": [],
  "estimated_at": 1777150279.44,
  "note": "Token sayisi tahmini (1500 avg, 30/70 split). 016+ gercek token tracking."
}
```

### 2. `learnings_log` (MCP) — bugfix entry → ok:true, hash returned
```json
{"ok": true, "hash": "7eda77a1f674"}
```

### 3. `learnings_recent` (MCP) — 1 entry + stats
```json
{
  "recent": [{
    "ts": 1777150279.45, "category": "bugfix",
    "lesson": "015 smoke test ders kaydi",
    "source": "mcp_tool", "project": null,
    "hash": "7eda77a1f674"
  }],
  "stats": {"total": 1, "by_category": {"bugfix": 1}, "last_30d": 1, "last_7d": 1}
}
```

### 4. `cache_stats` (MCP) — init values (boot sonrası kullanılmadı)
```json
{"hits": 0, "misses": 0, "entries": 0, "hit_rate_pct": 0.0}
```

MCP tools/list = **99**. Tüm 4 tool live JSON döndü.

## Notlar Planlayıcıya

1. **Manifest private key kullanıcıya elden teslim edildi** — `/tmp/abs-015-manifest-keys/private.pem` dosyasını **1Password / hardware token / encrypted offsite**'a taşıyın, `/tmp/`'tan silin. summary.md'ye REDACTED yazıldı, repo'ya commit yapılmadı (`.gitignore`'da `manifest-keys/` + exception only `manifest_pubkey.pem`).

2. **Cost estimator 1500 avg token varsayım** — gerçek tracking 016+'da `tracker.bump(name, tokens_in, tokens_out)` parametre uzantısı ile. Stream.py budget event'inde `today_usd` artık random değil, fakat absolute değil — projected_monthly tahmini olarak güvenilir.

3. **Learnings hook entegrasyonu opsiyonel atlandı** — `delegate_nudge.py` patch'i bu task'ta YAPILMADI. Manuel API + MCP tool yeterli. 016+'da hook trigger eklenebilir.

4. **Cache integration cascade orchestrator-level** — `basic_providers.ask_*` doğrudan provider çağrısı cache'siz (intentional). `call_with_cascade` (cohere_command_r vb.) cache aktif. Cache değeri tek-shot non-deterministik LLM yanıtlarında düşük; tasarım kabul.

5. **Watchdog deploy.sh test edilmedi** — manuel infra script. CI'da shellcheck ile syntax kontrol opsiyonel. `bash -n deploy.sh` syntax-only check eklenebilir 016+.

6. **Update signature default True (production)** — dev/test için `ABS_UPDATE_SIGNATURE_REQUIRED=false`. Live smoke `false` ile boot edildi. Müşteri production deploy `true` (default).

7. **Manifest pubkey embedded** — `app/update/manifest_pubkey.pem` repo'ya commit edildi (.gitignore exception). Key rotation senaryosu: yeni private + public gen → public.pem'i app/update/'a kopyala → yeni release imzala → eski müşterilerin update flow'u "signature invalid" der → 016+'da multi-pubkey transition window düşünülebilir.

8. **Cache stats hit oranı küçük** — production'da identical prompt nadir; cache TTL 5dk, max_entries 100. Optimizasyon değeri düşük; semantic similarity (embedding-based) cache 016+'a.

9. **Daily cost stream her 2sn'de tracker.snapshot çağırıyor** — high RPS senaryosunda CPU ısınması. Cache 30s ekleme 016+'da.

10. **`update_pending.json` flag'i 014'te eklenmişti** — host-side cron pickup'ı belgelendi 015'te `docs/operations.md § 12`. Müşteri host'ta cron veya systemd unit yazmalı.

## Feature Parity

015 SERVER paritesinden ileriye geçer:
- Cost estimator: SERVER yok (orchestrator localhost'ta cost yönetimi yok)
- Learnings store: ABS-specific (panel learnings_count badge için)
- Manifest signature: ABS-specific (release supply-chain güvenliği)
- Watchdog deploy: ABS-specific (Automatia Central Watchdog)

Atlanan parity yok.

## Doğrulama (Fail-Fast)

```bash
$ .venv/bin/pytest -q
247 passed, 2 skipped in 6.56s

$ .venv/bin/python -c "from app.mcp.server import _REGISTERED_COUNT; print(_REGISTERED_COUNT)"
99

$ test -f app/update/manifest_pubkey.pem && echo "pubkey OK"
pubkey OK

$ test ! -f app/update/manifest_private.pem && echo "private NOT in repo"
private NOT in repo

$ ls /tmp/abs-015-manifest-keys/
private.pem  public.pem    # private kullanıcıya, public app/update/manifest_pubkey.pem'e kopyalandı
```

Hepsi yeşil.

## Kapsam Dışı (016+'a)

- Symbol graph real implementation (AST parser, neighbors, search)
- RAG hybrid (BM25 + cosine)
- ML-based persona training (logistic regression on outcome)
- Real token tracking (`tracker.bump(name, tokens_in, tokens_out)`)
- Multi-channel release tracks (stable/beta/canary)
- Watchdog real scrape parsers (provider başına custom)
- Cost estimator daily cache (CPU optimizasyon)
- Multi-pubkey transition window (key rotation grace period)
- Encryption key rotation cron
- Hook delegate_nudge → learnings.log integration
