# Task 022 — Deferred Cleanup (7+ Edge Cases Batch)

**Status:** READY (Worker)
**Tahmini süre:** 3-4 saat
**Bağımlı task'lar:** 010-021 hepsi (deferred notlar her task'tan toplanır)
**Hedef sonuç:** 010-021 boyunca "X+'a deferred" diye işaretlenmiş edge case'leri tek pakette adresle. Production hardening + technical debt cleanup.

---

## 0. Bağlam

010-017'de 13+ "022+'a deferred" notu birikti. 018-021'de muhtemelen 5+ daha eklenir. Tek tek minor task açmak yerine batch cleanup. Hedef: production-ready debt-free state.

**017'den deferred:**
1. Net revenue (refund subtraction + Stripe fees) — gross hesaplanıyor
2. Stripe coupon programatik (FIRST50 manuel)
3. WebhookEvent purge cron (90 gün retention)
4. Demo countdown manuel reset prosedürü
5. Setup wizard adım metrikleri (drop-off analizi)
6. Annual billing (recurring Price)
7. `metadata.license_jti` checkout flow zorunlu kılma
8. Email open/click tracking

**011'den deferred:**
9. License `GET /v1/license/status` revoked_at raporu (012'de eklenmedi)

**015'ten deferred:**
10. Panel placeholder `_build_orchestrator.judge` real senior_judge entegrasyonu

**016'dan deferred:**
11. TS/JS symbol parsing (Python only şu an)

---

## 1. Amaç (DoD)

8 edge case modülü kapatılmalı (paket olarak). Her modül 1-3 dosya değişiklik + 2-4 test.

---

## 2. Modüller

### Modul A — Net Revenue (Refund + Fees)
`app/mcp/tools/billing_tools.py::_compute_revenue` extend:
- `revoked_at != None` lisansları gross_usd'den DÜŞ
- Stripe %2.9 + $0.30 fee her başarılı checkout için tahmini düş
- Output: `{gross, fees, refunds, net}`
- 2 test (3 lisans + 1 refund + fee → net hesabı)

### Modul B — WebhookEvent Purge Cron
`infra/scripts/purge_webhook_events.py`:
- 90 gün öncesini `WebhookEvent` tablosundan sil
- `processed_at IS NOT NULL` (orphan'ları tut)
- `infra/cron/purge_webhook.cron` weekly schedule
- 2 test (3 row + 1 eski → 1 silinir; orphan korunur)

### Modul C — Demo Reset Endpoint
`app/api/demo_admin.py`:
- `POST /v1/admin/demo/reset` — admin endpoint (Bearer admin_token)
- `data_dir/demo_state.json` sil
- Audit log entry
- 3 test (auth fail, success, idempotent)

### Modul D — Setup Wizard Metrics
`app/api/setup.py` patch:
- Her adım transitionunda `WizardEvent` row insert (step_num, started_at, completed_at)
- MCP tool `wizard_funnel` — drop-off oranı her adım için
- 3 test (event insert, funnel calc, edge step 6)

### Modul E — Annual Billing SKU
`infra/scripts/setup_stripe_products.py` extend:
- `--annual` flag → 3 yeni product (`self-host-annual` $2999, vb.)
- `_SKU_TO_PRICE` extend
- 2 test

### Modul F — License revoked_at Status
`app/api/license.py::license_status` patch:
- `revoked_at IS NOT NULL` → `{status: "revoked", revoked_at: ISO, reason: ...}`
- DB query gerekir (şu an saf JWT)
- 2 test

### Modul G — Senior Judge Real Integration
`app/api/panel.py::_build_orchestrator` patch:
- Placeholder `judge` field → `app.judge.senior.invoke()` real call
- Cache 60s
- 1 test

### Modul H — TS/JS Symbol Parsing
`app/symbols/parsers/typescript.py`:
- tree-sitter-typescript veya esprima ile basic parse
- function/class/variable extract
- `app.symbols.indexer` patch — `.ts/.tsx/.js/.jsx` extension recognize
- 3 test

---

## 3. Test Stratejisi

| Modül | Test |
|---|:-:|
| A | 2 |
| B | 2 |
| C | 3 |
| D | 3 |
| E | 2 |
| F | 2 |
| G | 1 |
| H | 3 |
| Tool count update | (1) |
| **TOPLAM** | **18** |

Toplam: 324 → 342.

Yeni MCP tool: `wizard_funnel` (Modul D) → tool count 105 → 106.

---

## 4. Smoke Evidence

1. `01_net_revenue.json` — billing_status with refund + fee subtraction
2. `02_purge_dry_run.json` — purge script --dry-run output
3. `03_demo_reset.json` — endpoint hit + state cleared
4. `04_wizard_funnel.json` — 6 adım drop-off
5. `05_ts_symbol_parse.json` — sample TS file → symbols extracted

---

## 5. Adım Adım

```
1. baseline pytest 324 + tool 105
2. Modul A → F (paralelize edilebilir, sırayla yap)
3. Modul G (senior_judge — judge module mevcut, integration küçük)
4. Modul H (TS/JS parsing — tree-sitter dependency büyük, opsiyonel: esprima light)
5. pytest 342 + tool 106
6. 5 smoke evidence
7. summary + completed/
```

## 6. DoD Checklist

```
[ ] 8 modül kapatıldı
[ ] 18 yeni test yeşil
[ ] tool count 106 (wizard_funnel eklendi)
[ ] backend regression yeşil (010-021)
[ ] 5 smoke evidence
[ ] summary + completed/
[ ] Open notes: TS/JS parser tree-sitter migration ileriki task'a (tree-sitter binary 50MB+)
```

## 7. Worker Notları

1. **Modul priorities** — A (revenue) ve F (license status) müşteri-facing, önce yap.
2. **Modul H esnek** — tree-sitter zor kuruluyorsa esprima (npm) veya basic regex ile başla, full tree-sitter 023+'a.
3. **Modul C admin auth** — Bearer token env'den (`ABS_ADMIN_TOKEN`), config.py'a ekle.
4. **WizardEvent table** — yeni SQLModel, boot create_all (017 pattern).
5. **CHANGELOG.md update** (020'de oluşturulmuştu) — 022 satırını ekle.
6. **Modul G** — `app/judge/senior.py` mevcut (008'de). Sadece import + cache wrapper.
7. **Hepsi backward compat** — eski endpoint/tool davranışları değişmez, yalnız extension.
