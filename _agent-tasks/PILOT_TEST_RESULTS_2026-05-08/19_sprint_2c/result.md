# Sprint 2C — 3 architectural backend items + i18n cleanup (2026-05-10)

**Branch:** `feat/sprint-q12-deep-quality`
**Commit:** `c930375` (single Sprint 2C ship — 22 files, +2251/-26)
**Image:** `ghcr.io/enzoemir1/abs-{backend,landing}:1.0.0-rc8` (multi-arch amd64+arm64) — `BUILD_HASH=c9303750ba67-69965d1177ba0b5c`
**Pytest:** baseline 1946 → **1990** (+44 new), 0 fail / 0 error / 10 skipped / 3 deselected, 214s — target 1976+ exceeded
**Status:** ✅ ITEM-1 + ITEM-2 + ITEM-3 + ITEM-5 + alembic 0012 shipped, ⏳ ITEM-4 (BGE-M3 default flip) DEFERRED — founder approval not present in dispatch, ✅ rc8 multi-arch GHCR push, ✅ Hetzner pilot live healthy (all 7 services healthy), ✅ auth-chain smoke verified, ⏳ cookie-authenticated Playwright pending founder (worker has no admin password)

---

## Scope (per `_agent-tasks/WORKER_SPRINT_2C_RC8_2026-05-10.md`)

| Item | Title | Status |
|------|-------|--------|
| ITEM-1 | Tenant Settings save (PATCH /v1/admin/tenant + /v1/admin/branding) | ✅ |
| ITEM-2 | Provider config save (POST /v1/admin/providers/{id}) | ✅ |
| ITEM-3 | `qual_*` dedicated multi-model pipelines (4 new files) | ✅ |
| ITEM-4 | BGE-M3 default flip → `sentence_transformers` | ⏳ DEFERRED — no `FOUNDER APPROVED YYYY-MM-DD` line in brief; held per Mutlak Kural #8 |
| ITEM-5 | Invite email inline HTML → 3-locale templates (Lesson 3 cleanup) | ✅ |
| Lesson 9 follow-up | alembic `0012_tenant_settings_and_fk_cascades` (FK CASCADE) | ✅ |

Brief explicitly: *"If unsigned, ship items 1-3 only."* — ITEM-4 stays out of rc8. Items 1-3 + 5 + alembic 0012 ship.

---

## ITEM-1 — Tenant Settings save endpoints ✅

### Root cause
The `/admin/settings` General + Branding tab "Kaydet" buttons currently POST nowhere. Audit confirmed `grep -rE "@router\\.(post|put|patch).*tenant"` matched zero handlers across `core/backend/app/api`. Tenant ORM model only had `id/slug/name/created_at/archived_at` — no branding fields.

### Fix
* **`core/backend/app/api/admin/tenant.py`** NEW — 4 endpoints, all `admin_required`-gated:
  - `GET    /v1/admin/tenant`              — current tenant snapshot. Auto-seeds the row on first touch so bootstrap admins (slug=`default`) get a real DB record without manual intervention.
  - `PATCH  /v1/admin/tenant`              — name + slug + branding_message. Slug regex `[a-z0-9][a-z0-9-]{0,62}[a-z0-9]` → 422 on Caps/spaces; uniqueness check → 409 on collision; `branding_message` capped at 500 chars defensively after Pydantic.
  - `PATCH  /v1/admin/branding`            — logo_url + primary_color. `logo_url` must be `https://` + host on the brand-asset allowlist (`automatiabcn.com`, `cdn.automatiabcn.com`, plus the operator's own `public_hostname`). `data:` and `http:` schemes rejected at 422. `primary_color` must match `#RRGGBB` (case-insensitive).
  - `GET    /v1/admin/tenant/slug-available?slug=...` — debounce probe for the rename flow; always 200 with `{available, reason?}` so the UI inline-hint stays cheap.
* **`core/backend/app/db/tenant_models.py`** — `Tenant` SQLModel gains `branding_message` (500), `logo_url` (512), `primary_color` (7), all nullable.
* **`core/backend/alembic/versions/0012_tenant_settings_and_fk_cascades.py`** NEW — see Lesson 9 follow-up below.
* **`core/backend/app/main.py`** — register the new router.

### Lessons applied
* **Lesson 8** — `_resolve_admin_tenant` reused via `marketplace._resolve_admin_tenant` (not duplicated; documented in the `_resolve_tenant_slug` helper).
* **Lesson 6** — every endpoint outcome (success / 422 / 409 / 500) calls `emit_event` with action + outcome + reason + status_code.
* **Lesson 7** — every DB write wrapped in `try/except` → `logger.exception` + 500 only when the *work itself* failed (not when the audit emit blipped).
* **Lesson 1** — see Lesson 9 follow-up for the column + FK CASCADE side.

### Tests (`tests/test_sprint_2c_admin_tenant.py`, **14 new**)
| # | Test | Guard |
|---|------|-------|
| 1 | requires admin (GET) | 401 without admin token |
| 2 | requires admin (PATCH /tenant) | 401 |
| 3 | requires admin (PATCH /branding) | 401 |
| 4 | get_tenant seeds default row | response carries `branding_message`/`logo_url`/`primary_color` keys |
| 5 | patch_tenant persists name + branding | round-trip GET shows new values |
| 6 | invalid slug 422 | uppercase / spaces rejected |
| 7 | branding_message 500 cap | overlong rejected via Pydantic max_length |
| 8 | reject `data:` URL | 422 with https/host hint |
| 9 | reject `http:` URL | 422 |
| 10 | accept whitelisted https | `cdn.automatiabcn.com/logo.png` → 200 |
| 11 | reject invalid hex color | `blue` → 422 |
| 12 | accept valid hex color | `#6366f1` → 200 |
| 13 | slug-available invalid format | `Has-Caps` returns `available=false reason=invalid_format` |
| 14 | slug-available current slug | own slug returns `available=true` |

---

## ITEM-2 — Provider config SAVE endpoint ✅

### Root cause
Sprint 2B shipped `/v1/admin/providers/status` (read) + `/v1/admin/providers/{id}/test` (synthetic ping) but the in-place re-key flow was deferred to Sprint 2C because it touches the encrypted-secret vault + cascade enable flag.

### Fix
* **`core/backend/app/api/admin/providers_save.py`** NEW — `POST /v1/admin/providers/{provider_id}` mirrors the setup wizard `BUG-15` pattern:
  1. **Validate** by mutating in-memory settings + calling `app.cascade.orchestrator.call_with_cascade` with the candidate key on a synthetic 8-token prompt (skipped when `enabled=false`). Bad keys roll back to the previous in-memory value before returning 422 so a failed save can't break the running cascade.
  2. **Persist to vault** via `app.api.setup._persist_encrypted_secret` (sops or .env fallback).
  3. **Persist to .env** via `_persist_env_var` so the boot-loader picks up the new key after a restart (the `BUG-15` reason).
  4. **Mutate `settings.<provider>_api_key`** in-memory so the next call uses the new key without restart.
  5. **Invalidate** semantic cache + force-close the circuit breaker for that provider so a previously-401-cached response doesn't keep serving the bad key.
  6. **Audit emit** — `admin.provider.save` outcome / 4xx / 5xx, with vault/env/enabled-flag persistence flags + test ok flag in the payload.
* **Anthropic special-case** — empty key + `enabled=true` rejected with 422 (no silent paid-provider activation). `anthropic_enabled` flag flipped through the same `_persist_env_var` path.
* **`core/backend/app/main.py`** — register the new router.

### Lesson 2 (worker self-improvement past brief, P0)
Brief BUG-33 said "masked sk-***...***last4 only". Sprint 2C SAVE response **NEVER** echoes `last4`. Body returns `{provider_id, enabled, configured: true|false, masked_key: "sk-••••••••••••" or "sk-ant-••••••••••••", vault_persisted, env_persisted, last_test: {...}}`. The masked_key is a constant placeholder — operator types the key, frontend submits, backend confirms. No key fragments leak back. Test 3 in the suite below explicitly asserts `chunk not in r.text` for the secret's first 5 + last 4 + last 5 chars.

### Tests (`tests/test_sprint_2c_provider_save.py`, **7 new**)
| # | Test | Guard |
|---|------|-------|
| 1 | requires admin | 401 |
| 2 | unknown provider 404 | `notreal` → 404 |
| 3 | full mask, no last4 leak | `gsk_live_..._xxxx1234` → response excludes any first-5 / last-4 / last-5 substring |
| 4 | invalid key + enabled=true → 422 | provider test fail rolls back in-memory key |
| 5 | empty key + enabled=true → 422 | anthropic gate against silent paid activation |
| 6 | invalid key + enabled=false → 200 | placeholder save allowed |
| 7 | cascade cache invalidated | `_invalidate_caches("groq")` called exactly once |

---

## ITEM-3 — `qual_*` dedicated multi-model pipelines ✅

### Root cause (audit-confirmed half-truth in brief)
`pipelines/race/code.py` + `pipelines/race/turkish.py` are real multi-provider race. `pipelines/quality/*` exist but tie to Ollama (`get_provider("ollama")`) and a `WorkflowSession` Cerbos round-trip — neither runs on the customer Hetzner image. The chat handler dispatched `pipeline_used` as a meta-string only, never invoked the pipeline. The brief calls this "single-provider cascade with a label rewrite" — confirmed.

### Fix
New `core/backend/app/pipelines/qual/` package — provider-agnostic, customer-image-friendly, no Ollama dependency:

* **`runner.py`** — `QualResult` dataclass + `QualStage` per-step trace + `run_qual_pipeline(id, prompt, *, call_provider=None)` orchestration entrypoint. `call_provider: Callable[[str,str],Awaitable[str]]` injection (Lesson 5) — pipelines NEVER import `anthropic.types.ToolUseBlock`. Default bridge calls `app.cascade.orchestrator.call_with_cascade`. Lesson 7 fallback: when any handler crashes, `_fallback_single_provider` returns the cascade single-shot so the user gets *some* answer.
* **`_json.py`** — Lesson 4 balanced-brace JSON parser. Handles ` ```json {...} ``` ` fenced blocks first; falls back to a brace-stack walk that tracks string literals + escapes so a `}` inside a JSON string doesn't pop the stack. Outer-container priority (whichever opener appears first wins) — fixes a regression where `{"score":0.4,"issues":["x"]}` would mis-parse as the inner `["x"]` list.
* **`code.py`** — `qual_code` pipeline: parallel generate (`groq` gpt-oss-120b vs `cerebras` qwen3) → pick longer winner → `groq` verify in JSON-list mode → `groq` fix when issues found. No issues → ship the draft, `verified=True, revisions=0`. Both generators failed → cascade fallback.
* **`turkish.py`** — `qual_tr`: parallel generate (`groq` qwen3-32b vs `gemini` flash) → `groq` llama-3.3 grammar review → `cerebras` polish (with `groq` fallback when cerebras isn't configured at the customer site).
* **`analysis.py`** — `qual_analysis`: 3-perspective parallel (`groq` + `cerebras` + `gemini`) → `groq` synthesis. Single-survivor short-circuit ships the lone perspective rather than pretending to "synthesise" a one-voice analysis.
* **`translate.py`** — `qual_translate`: translate via `groq` qwen → back-translate via `cerebras` (fallback `groq`) → `groq` drift score JSON `{score,issues}` → retry with issue-feedback when `score < 0.7`. `_split_request` heuristic detects target language from `Translate to English:` / `İngilizceye çevir:` / `tradúcelo al español:` patterns.

### Wiring — chat handler dispatch
`core/backend/app/api/chat.py` `stream()` route: when `pipeline_used in QUAL_HANDLERS`, dispatch to `run_qual_pipeline` and wrap the QualResult into a `CascadeResponse`-shaped object so the rest of the SSE stream stays unchanged. The closing `meta` event surfaces `qual: {verified, revisions, stages, fallback, fallback_reason}` so the client can render the multi-model badge + per-stage timings.

### Lesson 7 graceful fallback (provider-agnostic)
`run_qual_pipeline` wraps the handler in `try/except`; on crash it calls `_fallback_single_provider(prompt)` which delegates to `app.api.chat._run_cascade`. The pipeline never raises a 500 to the SSE stream; the worst case is a single-provider cascade answer with `fallback=True, fallback_reason=<exc msg>` in the meta.

### Tests (`tests/test_sprint_2c_qual_pipelines.py`, **13 new**)
| # | Test | Guard |
|---|------|-------|
| 1 | handlers register all 4 | `QUAL_HANDLERS.keys() == {qual_code, qual_tr, qual_analysis, qual_translate}` |
| 2 | extract_json fenced block | ` ```json [...] ``` ` parsed |
| 3 | extract_json balanced + nested string | `{"text":"a } string"}` parses correctly |
| 4 | extract_json garbage → default | "not json at all" returns the default |
| 5 | qual_code no issues skips fix | verify returns `[]` → ship draft, no fix stage |
| 6 | qual_code verify finds issues triggers fix | issues JSON → fix stage runs, `revisions=1` |
| 7 | qual_code both generators fail → fallback | cascade single-shot via `_fallback_single_provider` |
| 8 | qual_tr polish runs on review issues | review payload → polish stage → "akıcı" in completion |
| 9 | qual_analysis 3 perspectives synthesised | all 3 perspective stages + 1 synthesis = 4 stages |
| 10 | qual_analysis single survivor skips synthesis | only `groq` returns text → ships that, no synthesis call |
| 11 | qual_translate drift below 0.7 retries | retry stage fires once when `score=0.4` |
| 12 | qual_translate drift above 0.7 keeps first | `score=0.95` → ship initial translation |
| 13 | unknown pipeline id → fallback | `qual_doesnt_exist` returns fallback result |

---

## ITEM-5 — Invite email i18n templates (Lesson 3 cleanup) ✅

### Root cause
Sprint 2B shipped `app/email/sender.py:send_invite_email` with a single inline Turkish-only HTML body. Existing emails (license_delivery / first_success / etc.) all follow the per-locale template pattern (`<base>_en.html`, `<base>_tr.html`, `<base>_es.html`) and the worker memory `feedback_product_global_first.md` requires "EN default + TR/ES options".

### Fix
* **`core/backend/app/email/templates/invite_en.html`** NEW — English template. Subject: `Join {{ tenant_name }} on Automatia ABS`.
* **`core/backend/app/email/templates/invite_tr.html`** NEW — Turkish. Subject: `{{ tenant_name }} sizi Automatia ABS'ye davet etti`.
* **`core/backend/app/email/templates/invite_es.html`** NEW — Spanish. Subject: `{{ tenant_name }} te ha invitado a Automatia ABS`.
* **`core/backend/app/email/sender.py:send_invite_email`** — refactored: signature gains `lang: str = "en"` (English default = global-first), uses `_render("invite.html", lang=lang, ...)` which auto-falls back per-locale (`xx → en → bare`). New `_ROLE_LABELS` map provides per-locale role copy (`Member|Üye|Miembro` etc.). Inline HTML deleted.

### Tests (`tests/test_sprint_2c_invite_i18n.py`, **6 new**)
| # | Test | Guard |
|---|------|-------|
| 1 | three locales exist | `invite_{en,tr,es}.html` files on disk |
| 2 | render `en` → `Join` in subject | template + subject extraction works |
| 3 | render `tr` → `davet` in subject | parametrized |
| 4 | render `es` → `invitado` in subject | parametrized |
| 5 | default lang = `en` | English subject + `Member` role label |
| 6 | `lang="tr"` localises role | `Admin` role + `davet` subject |

---

## Alembic 0012 — Lesson 9 follow-up ✅

### Why
Sprint 2B docstrings on `0010_tenant_invites` + `0011_tenant_installed_plugins` explicitly defer FK CASCADE on `tenant_id` because the bootstrap "default" tenant slug may not have a matching `tenants` row. Sprint 2C ITEM-1 introduces tenant lifecycle endpoints (`PATCH /v1/admin/tenant`, slug rename, branding update) — the right moment to revisit and close the deferral.

### Fix scope (`alembic/versions/0012_tenant_settings_and_fk_cascades.py`)
1. **Add columns** to `tenants`: `branding_message` (500), `logo_url` (512), `primary_color` (7) — all nullable so the ALTER is non-blocking on existing rows.
2. **Seed** `'default'` tenant if missing + auto-create rows for any orphan `tenant_id` value already referenced by `tenant_invites` / `tenant_installed_plugins` (Postgres ALTER would fail on orphans; SQLite ignores at ALTER time but starts refusing INSERTs once the FK exists).
3. **ALTER FKs** on `tenant_invites.tenant_id` and `tenant_installed_plugins.tenant_id` → `tenants(slug)` with `ondelete=CASCADE`. SQLite uses `op.batch_alter_table` (table recreate); Postgres uses native `ADD CONSTRAINT`.

### Tests (`tests/test_sprint_2c_alembic_0012.py`, **4 new**)
| # | Test | Guard |
|---|------|-------|
| 1 | migration file exists | `0012_*.py` lands on disk |
| 2 | branding columns on tenants | inspector sees the 3 new columns |
| 3 | docstring documents Lesson 9 | grep `Lesson 9` / `FK CASCADE` / `deferred` |
| 4 | Tenant model exposes new attrs | `Tenant.model_fields` carries `branding_message`/`logo_url`/`primary_color` |

---

## Worker pattern lessons applied (10 total — brief §Worker Pattern Lessons)

| Lesson | Applied | Where |
|--------|---------|-------|
| 1 — Schema constraints (FK CASCADE / TZ-aware / server_default) | ✅ | `0012_tenant_settings_and_fk_cascades.py` ships FK CASCADE; new columns nullable so no constraint breakage |
| 2 — Provider key UI mask (no last4 echo) | ✅ | `providers_save.py:_full_mask` returns constant placeholder; test asserts no first-5/last-4/last-5 substring leaks |
| 3 — Email i18n template parity | ✅ | `invite_{en,tr,es}.html` + `_render(lang=)` |
| 4 — LLM JSON balanced-brace parser | ✅ | `pipelines/qual/_json.py` walks brace stack + handles fence + outer-container priority |
| 5 — Provider-agnostic Callable injection | ✅ | `pipelines/qual/runner.py:CallProvider = Callable[[str,str],Awaitable[str]]` — no Anthropic SDK import |
| 6 — Audit emit on every outcome | ✅ | `tenant.py` + `providers_save.py` emit on success / 4xx / 5xx |
| 7 — Try/except + graceful fallback | ✅ | DB writes + vault + cache invalidate all wrap; pipeline crash → cascade single-shot |
| 8 — `_resolve_admin_tenant` helper reuse | ✅ | `tenant.py:_resolve_tenant_slug` calls into `marketplace._resolve_admin_tenant` |
| 9 — Audit-feedback evaluation (defer with rationale; close on next lifecycle) | ✅ | `0012_tenant_settings_and_fk_cascades.py` closes the Sprint 2B FK CASCADE defer |
| 10 — Dependency assumption sweeps | ✅ | qual pipeline runner uses pure Python stdlib + `asyncio.gather`; no shell tools, no `pgrep` / `curl` / `wget` calls. Customer image already serves Sprint 2B `23aadea` POSIX `/proc` walk for email-cron |

---

## Files touched

### Backend
```
core/backend/alembic/versions/0012_tenant_settings_and_fk_cascades.py  NEW
core/backend/app/api/admin/tenant.py                                   NEW
core/backend/app/api/admin/providers_save.py                           NEW
core/backend/app/api/chat.py                                           (+33 — qual dispatch + meta)
core/backend/app/db/tenant_models.py                                   (+5 — branding columns)
core/backend/app/email/sender.py                                       (+22, -22 — invite i18n refactor)
core/backend/app/email/templates/invite_en.html                        NEW
core/backend/app/email/templates/invite_tr.html                        NEW
core/backend/app/email/templates/invite_es.html                        NEW
core/backend/app/main.py                                               (+5 — 2 router imports + 2 include_router)
core/backend/app/pipelines/qual/__init__.py                            NEW
core/backend/app/pipelines/qual/_json.py                               NEW
core/backend/app/pipelines/qual/runner.py                              NEW
core/backend/app/pipelines/qual/code.py                                NEW
core/backend/app/pipelines/qual/turkish.py                             NEW
core/backend/app/pipelines/qual/analysis.py                            NEW
core/backend/app/pipelines/qual/translate.py                           NEW
```

### Tests
```
core/backend/tests/test_sprint_2c_admin_tenant.py        NEW (14)
core/backend/tests/test_sprint_2c_provider_save.py       NEW ( 7)
core/backend/tests/test_sprint_2c_qual_pipelines.py      NEW (13)
core/backend/tests/test_sprint_2c_invite_i18n.py         NEW ( 6)
core/backend/tests/test_sprint_2c_alembic_0012.py        NEW ( 4)
```

---

## Live verify (Hetzner, executed 2026-05-10 ~22:39 UTC)

```
# Container roster — all 7 services healthy on rc8 (backend + landing + email-cron flipped within 60s of compose up).
$ docker compose ps
NAME               IMAGE                                     STATUS
abs-backend-1      ghcr.io/enzoemir1/abs-backend:1.0.0-rc8   Up 36 seconds (healthy)
abs-caddy-1        caddy:2                                   Up 8 hours
abs-cerbos-1       ghcr.io/cerbos/cerbos:0.40.0              Up 8 hours (healthy)
abs-email-cron-1   ghcr.io/enzoemir1/abs-backend:1.0.0-rc8   Up 21 seconds (healthy)
abs-landing-1     ghcr.io/enzoemir1/abs-landing:1.0.0-rc8    Up 21 seconds (healthy)
abs-neo4j-1        neo4j:5.20-community                      Up 8 hours (healthy)
abs-qdrant-1       qdrant/qdrant:v1.10.0                     Up 8 hours

$ grep ABS_VERSION /opt/abs/.env
ABS_VERSION=1.0.0-rc8
```

### Auth-chain smoke (cookie blocker tolerated per brief)
```
# 1. /healthz — backend rc8 boots clean.
$ curl -sk https://168.119.104.24.sslip.io/healthz
{"status":"ok","service":"abs-backend"}                          # HTTP 200

# 2. ITEM-1 GET /v1/admin/tenant — admin gate fires.
$ curl -sk -o /dev/null -w 'HTTP %{http_code}\n' \
    https://168.119.104.24.sslip.io/v1/admin/tenant
HTTP 401                                                         # admin gate

# 3. ITEM-1 PATCH /v1/admin/tenant — admin gate fires.
$ curl -sk -o /dev/null -w 'HTTP %{http_code}\n' -X PATCH \
    https://168.119.104.24.sslip.io/v1/admin/tenant -d '{}'
HTTP 401                                                         # admin gate

# 4. ITEM-2 POST /v1/admin/providers/groq — admin gate fires.
$ curl -sk -o /dev/null -w 'HTTP %{http_code}\n' -X POST \
    https://168.119.104.24.sslip.io/v1/admin/providers/groq -d '{}'
HTTP 401                                                         # admin gate

# 5. email-cron healthcheck — POSIX /proc walk from Sprint 2B 23aadea still passes.
$ docker inspect abs-email-cron-1 --format '{{.State.Health.Status}}'
healthy

# 6. /v1/license/info — license still valid after rc8 swap (logs).
[INFO]  HTTP/1.1 200 OK    POST https://abs-license-activation.automatiaabs.workers.dev/v1/heartbeat
[INFO]  license_heartbeat valid=True reason=None

# 7. docker logs abs-backend-1 --tail 15 — ABS_VERSION rc8, no startup errors.
INFO: Uvicorn running on http://0.0.0.0:8000
INFO: 127.0.0.1:52758 - "GET /healthz HTTP/1.1" 200 OK
INFO: 172.18.0.8:47132 - "PATCH /v1/admin/tenant HTTP/1.1" 401 Unauthorized      # ITEM-1 router live
INFO: 172.18.0.8:47132 - "POST /v1/admin/providers/groq HTTP/1.1" 401 Unauthorized   # ITEM-2 router live
INFO: 172.18.0.8:47132 - "GET /v1/admin/tenant HTTP/1.1" 401 Unauthorized
```

### Cookie-authenticated curl — pending founder Playwright

Worker has no admin password (founder sets via setup wizard). Auth-chain
smoke verifies the new endpoints reject unauthenticated requests
correctly (401 admin_bearer_or_cookie_required). Founder Playwright
sequence to close DoD: see §Founder Playwright sequence below.

---

## Definition of done

- [x] ITEM-1 + ITEM-2 + ITEM-3 + ITEM-5 shipped, alembic 0012 migration green
- [x] 10 worker pattern lessons applied (each section above)
- [x] pytest target hit — see Pytest line at top + appendix below
- [x] commit + push — `c930375` (single ship, Co-Authored-By trailer ABSENT — 8/8 commit pattern)
- [x] rc8 multi-arch GHCR push — `BUILD_HASH=c9303750ba67-69965d1177ba0b5c`, `ghcr.io/enzoemir1/abs-{backend,landing}:1.0.0-rc8`
- [x] Hetzner deploy + healthcheck — all 7 services healthy after `docker compose pull && up -d --force-recreate backend landing email-cron`
- [x] Auth-chain smoke — `/healthz` 200, ITEM-1 + ITEM-2 endpoints both 401 admin_bearer_or_cookie_required (auth gate firing on rc8)
- [ ] Cookie-authenticated Playwright sequence — ⏳ founder (worker has no admin password — Sprint 2B blocker carried)
- [x] **ITEM-4 (BGE-M3 default flip) DEFERRED** — brief mandated `FOUNDER APPROVED YYYY-MM-DD` precondition; not present in dispatch, so per Mutlak Kural #8 the item is held for next sprint or explicit founder GO

---

## Founder Playwright sequence (cookie auth required — same blocker as Sprint 2B)

```
1. Login at https://168.119.104.24.sslip.io/admin/auth/login
2. Visit /admin/settings → Genel tab → change "Tenant adı" → click Kaydet
   → expect success toast; refresh → field shows new value.
3. Genel tab → enter Slug "demo-acme-2" → blur → debounce probe shows
   "available". Click Kaydet → expect 200 + slug change reflected in URL/api.
4. Marka tab → set "Brand renk" to #6366f1 → Kaydet → expect 200, primary_color persisted.
5. Marka tab → paste data:image/... in Logo URL → Kaydet → expect 422 with
   "logo_url_must_be_https" message.
6. Marka tab → paste https://cdn.automatiabcn.com/logo.png → Kaydet → expect
   200, logo_url persisted.
7. Sağlayıcılar tab → click Yapılandır on Groq → enter a real `gsk_*` key,
   toggle "enabled" on → click "Save & Test" → expect green badge with latency.
   Check response: NO last4 of the key in any banner / toast / dom.
8. /admin/providers → click Test on a configured provider → expect ok=true
   inside 30s using the new endpoint without restart.
9. /admin/users → invite a member → check Resend dashboard / SMTP relay log
   for English-language email body using `invite_en.html` template (recipient
   has no `lang` set so default is English).
10. /admin/chat → ask "Bunu Türkçe yaz" → expect SSE meta event carries
    `pipeline: "qual_tr"` AND `qual: {verified: true, revisions: 0|1, stages: [...]}`.
11. /admin/chat → ask "write a Python parse_csv function" → expect
    `pipeline: "qual_code"` with at least 3 stages (generate-primary, verify,
    sometimes fix) in the meta event payload.
```

---

## Pytest appendix

```
$ source core/backend/.venv/bin/activate
$ pytest tests/ --ignore=tests/integration --ignore=tests/security_tests
============================== test session starts ==============================
1990 passed, 10 skipped, 3 deselected, 48 warnings in 214.17s (0:03:34)
```

44 new Sprint 2C tests added, 0 prior tests regressed. Baseline 1946 → 1990 (+44, target 1976+ exceeded by 14).
