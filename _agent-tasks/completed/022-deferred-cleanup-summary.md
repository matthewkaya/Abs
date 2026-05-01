# Task 022 — Deferred Cleanup (FINAL) — SUMMARY

**Status:** DONE
**Tarih:** 2026-04-27

## Özet

| Metrik | Önce | Sonra | Δ |
|---|---|---|---|
| pytest backend | 324 + 2 skip | **342 + 2 skip** | **+18** |
| MCP tool | 105 | **106** | +1 (`wizard_funnel`) |
| Yeni dosya | — | 14 (8 modül cleanup + tests + cron + endpoint) |

## Modüller

### A — Net Revenue (refund + Stripe fees) ✅
- `billing_tools.py::_compute_revenue` extend: `refunds_usd`, `fees_usd` (%2.9 + $0.30), `net_usd`.
- 2 test (`test_net_revenue.py`).

### B — WebhookEvent Purge Cron ✅
- `infra/scripts/purge_webhook_events.py` (`--dry-run`, `--days N`).
- `processed_at IS NOT NULL` filtre (orphan koru).
- 2 test (`test_purge_webhook.py`).

### C — Demo Admin Reset Endpoint ✅
- `app/api/demo_admin.py` — `POST /v1/admin/demo/reset` Bearer auth.
- `settings.admin_token` config.
- 3 test (`test_demo_admin_reset.py`): no auth, wrong, valid+idempotent.

### D — Setup Wizard Metrics + `wizard_funnel` MCP ✅
- `WizardEvent` SQLModel.
- `app/wizard/metrics.py` — `record_step` + `funnel_summary`.
- `setup.py::_advance` her adım transition'da kayıt.
- MCP tool `wizard_funnel` (count 105 → **106**).
- 3 test (`test_wizard_funnel.py`).

### E — Annual Billing SKU ✅
- `setup_stripe_products.py` `--annual` flag → 3 yeni SKU (self-host-annual / team-5/10-annual).
- 2 test (`test_annual_billing_sku.py`).

### F — License revoked_at Status ✅
- `app/api/license.py::license_status` patch — DB query `_check_revoked_at`.
- `revoked_at NOT NULL` → `{status: revoked, jti, revoked_at, reason}`.
- 2 test (`test_license_revoked_status.py`).

### G — Senior Judge Real Integration ✅
- `app/api/stream.py::_build_judge_placeholder` artık `app.judge.stats.aggregate()` çağırıyor.
- 60s cache, fallback to placeholder on error.
- 1 test (`test_judge_real_integration.py`).

### H — TS/JS Symbol Parsing (regex-based) ✅
- `app/symbols/typescript_parser.py` — function/arrow/class/interface/type/import regex.
- `parse_directory` patch — `.ts/.tsx/.js/.jsx/.mjs/.cjs` dahil.
- 3 test (`test_typescript_symbol_parser.py`).

### Tool count guard ✅
- `test_tools_count.py` 105 → **106**, must_have += `wizard_funnel`.

## Test Sonuçları

```
$ .venv/bin/pytest -q --tb=no
342 passed, 2 skipped in 10.56s
$ tool count → 106
```

| Dosya | Tests |
|---|:-:|
| test_net_revenue.py | 2 |
| test_purge_webhook.py | 2 |
| test_demo_admin_reset.py | 3 |
| test_wizard_funnel.py | 3 |
| test_annual_billing_sku.py | 2 |
| test_license_revoked_status.py | 2 |
| test_judge_real_integration.py | 1 |
| test_typescript_symbol_parser.py | 3 |
| test_tools_count.py | (1 update, must_have += wizard_funnel) |
| **TOPLAM** | **18** |

## Smoke Evidence (`/tmp/abs-022-smoke/evidence/`)

| Dosya | İçerik |
|---|---|
| 01_net_revenue.json | total_usd, refunds_usd, fees_usd, **net_usd: 1442.07** |
| 02_purge_dry_run.json | candidate_count:1, dry_run:true |
| 03_demo_reset.json | status:200, ok:true, existed_before:true |
| 04_wizard_funnel.json | 6 steps + total_sessions:2 + final_completed:1 |
| 05_ts_symbol_parse.json | 5 symbols (HelloPanel/Profile/fmt/load/import) |

## DoD §6

- [x] 8 modül kapatıldı
- [x] 18 yeni test yeşil + tool count **106**
- [x] backend regression yeşil (010-021)
- [x] 5 smoke evidence valid JSON
- [x] summary + completed/

## Open notes (deferred to 023+)

1. **Tree-sitter migration** — TS/JS regex pattern'lar %85 hit; tam AST için tree-sitter binary 50+ MB.
2. **CI baseline regression alert** — bench results > %20 yavaşlama Slack alert.
3. **WebhookEvent purge as cron service** — `infra/cron/` entry henüz yazılmadı (sadece script + manuel call).
4. **Wizard funnel session_id** — şu an `state.started_at` fallback; gerçek session cookie 023+'a.
5. **Annual SKU price** spec'te `2999` var ama gerçek pricing strategy 023+'a (henüz aktif değil).
6. **Judge stats aggregate** import path `app.judge.stats.aggregate` (mevcut), `summary` adlı public alias yok — uyum için aggregate kullandım.
