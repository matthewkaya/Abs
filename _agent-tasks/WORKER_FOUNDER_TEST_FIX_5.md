# Founder Tester — Fix Round 5 (BUG-10 follow-up)

> Round 4 final big test: **14/16 PASS**. BUG-10 marketplace tenant scope HALA FAIL.
> Branch: feat/sprint-q12-deep-quality (HEAD d000008, 1788 PASS)

## 0. Doğrulama

```
cd core/backend && ./.venv/bin/python -m pytest --no-header -q \
  --ignore=tests/test_providers.py \
  --ignore=tests/test_q03_real_saas_backends.py \
  --ignore=tests/test_update_channel.py
```

Round summary: pytest_full_suite + image_rebuilt_at + live_path_verified ZORUNLU.

## 1. BUG-10 (devam) HIGH — bootstrap admin tenant resolution

### Founder evidence
```
phaseD install: container_id=e07a1bd9...  (POST /install with tenant=demo-acme query param)
phaseD tenant scope: tenant=default  ← FAIL (expected demo-acme)
phaseD installed listed: gmail-archiver present=false  ← FAIL
```

### Root cause
`marketplace.py::_resolve_admin_tenant()` chain:
1. JWT claim `admin.get("tenant")` → None (login JWT'sinde tenant yok)
2. DB lookup: `email + status==active` → row YOK (bootstrap admin file-based)
3. Fallback → "default"

**Bootstrap admin** setup wizard'dan gelir → kayıt `/app/data/admin_credentials.json`'da, **User tablosunda DEĞİL**. Production customer için aynı path.

### Fix önerisi (2 katmanlı)

**A) JWT mint'e tenant claim ekle (login + magic-link path):**
- Login handler bootstrap admin için `setup_state.json`'dan tenant_slug oku
- JWT payload `{"sub": email, "tenant": tenant_slug}` 
- Resolver claim'i hemen kullanır

**B) `_resolve_admin_tenant()` fallback chain'e admin_credentials.json oku:**
- User table miss → `admin_credentials.json` + `setup_state.json` cross-check
- Setup wizard tamamlanmış + bootstrap admin email match → tenant_slug from license/domain step
- Bulunamazsa "default" fallback

Worker tercih A+B (ikisi birlikte güvenli).

### Test
```python
def test_bootstrap_admin_tenant_scope(client_bootstrap):
    """Bootstrap admin → marketplace installed scoped to setup tenant."""
    # Login as admin@demo-acme.com (admin_credentials.json file-based)
    r1 = client.post("/v1/marketplace/install", json={"plugin_id": "slack-receiver"})
    assert r1.status_code == 201
    r2 = client.get("/v1/marketplace/installed")
    body = r2.json()
    assert body["tenant"] == "demo-acme"
    assert any(p["plugin_id"] == "slack-receiver" for p in body["installed"])
```

### Verify
```
curl -sk -b /tmp/cookie.txt http://localhost:8000/v1/marketplace/installed
# Expected: {"tenant":"demo-acme", "installed":[{"plugin_id":"...", ...}]}
```

## 2. Round döngüsü

1. R1 = BUG-10 follow-up A+B
2. Pytest 1788 → ≥1789 (1 yeni test)
3. Image rebuild + container exec verify + dış-curl smoke
4. Founder Playwright Phase D re-run

## 3. Yasaklar

- Selective subset rapor → FULL CLEAN sayma (S11+S12 ders, hala risk)
- Image rebuild gate
- Bootstrap admin için query param zorunlu kılma — production customer bunu yapmaz
- Pilot/market/outreach gündem dışı
- L21 + Mutmut + DR actual: founder approval yok

## 4. Delegation %70+ MCP

- JWT claim mint + setup_state read: ask_gptoss
- Resolver fallback chain: ask_kimi
- Test fixtures: write_tests
- Patch judge: judge_patch

## 5. Başarı kriteri

- /v1/marketplace/installed cookie auth → tenant=demo-acme
- gmail-archiver listed
- Founder Playwright final big test: 16/16 PASS (was 14/16)
- Pytest ≥1789

## 6. Evidence

- /tmp/founder_final_big.json (14/16 PASS, 2 FAIL phaseD tenant)
- Round 4 round_2 raporu

## 7. Devam komutu

```
cd /Users/eneseserkan/Main/abs-server-product
git checkout feat/sprint-q12-deep-quality
cat _agent-tasks/WORKER_FOUNDER_TEST_FIX_5.md
docker exec infra-backend-1 cat /app/data/admin_credentials.json | head -5
docker exec infra-backend-1 cat /app/data/setup_state.json | head -10
```

Engelleyici YOK. Bu round sonrası tester teslimat eşik son MÜHÜR — final big test 16/16 PASS olur.
