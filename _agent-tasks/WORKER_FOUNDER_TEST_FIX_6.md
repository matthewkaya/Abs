# Founder Tester — Fix Round 6 (Bug-12 HIGH security + R5 commit)

> Round 5 final big test 13/14 PASS (1 script bug). 2 yeni bulgu:
> - Bug-12 HIGH magic-link claim → bootstrap admin_credentials.json OVERWRITE
> - Bug-13 LOW R5 fix uncommitted (Round 2 tekrarı)
>
> Branch: feat/sprint-q12-deep-quality (HEAD d000008, working tree dirty, 1790 PASS)

## 0. ÖNCELİK 0 — R5 git commit (uncommitted Round 5 fix)

```
cd /Users/eneseserkan/Main/abs-server-product
git status --short
# M auth.py M marketplace.py M test_marketplace_installed_tenant_scope.py + ?? founder_test_fix_5.md

git add core/backend/app/api/auth.py \
        core/backend/app/api/marketplace.py \
        core/backend/tests/test_marketplace_installed_tenant_scope.py
git commit -m "fix(founder-test/round-5): bootstrap admin tenant claim — JWT claim + 5-step resolver fallback — pytest 1788->1790"

git add _agent-tasks/WORKER_FOUNDER_TEST_FIX_5.md
git commit -m "docs(agent-tasks): Round 5 BUG-10 follow-up brief"
```

## 1. Bug-12 HIGH — magic-link claim bootstrap admin overwrite

### Founder evidence (2026-05-05)
Phase C signup test her run → `admin_credentials.json` overwrite ediliyor:
- Login öncesi: `{"email":"admin@demo-acme.com","source":"setup_wizard"}`
- Phase C `/auth/signup` + `/auth/magic?token=...` claim sonrası:
  - `{"email":"final-1778013113205@digisfer.local","source":"magic_link_claim"}`
- Sonuç: `admin@demo-acme.com / DemoPass2026!` login 401 — bootstrap admin **kayıp**.

Production senaryosu: setup wizard'la admin oluşturulur → herhangi biri `/auth/signup` + magic claim ile bootstrap admin'i ele geçirir. **Critical security issue.**

### Root cause
`core/backend/app/api/auth.py:511` `_claim_user_by_token`:
```
_admin_credentials_path().write_text(
    json.dumps({
        "email": user.email,
        "password_hash": user.password_hash,
        "created_at": time.time(),
        "tenant_slug": user.tenant_slug,
        "source": "magic_link_claim",
    }, ensure_ascii=False),
    encoding="utf-8",
)
```

Unconditional write. Her claim file'ı overwrite ediyor. Bootstrap admin silinir.

### Fix
Magic claim handler **sadece** bootstrap admin re-claim ise file'ı update etmeli, yeni admin'ler için DOKUNMAMALI:

```
# Read existing creds first
existing = _load_admin_credentials_raw() or {}
bootstrap_email = existing.get("email")

# Only write if claimed user IS the bootstrap admin (re-claim flow)
if bootstrap_email == user.email:
    _admin_credentials_path().write_text(...)
# Else: new admin lives in User table, no file write
```

Veya tamamen kaldır — User tablosu zaten claim sonrası `status="active"` set ediyor (auth.py:505). admin_credentials.json sadece setup wizard'ın bootstrap admin'i için. Magic claim için ayrı yer (User table) yeterli.

**Tercih:** if-bootstrap-only guard (geri uyumluluk).

### Test
```
def test_magic_claim_does_not_overwrite_bootstrap_admin(client_with_bootstrap):
    """Bug-12 — Phase C founder evidence: signup+claim bootstrap admin'i siliyordu."""
    # 1. Setup wizard creates bootstrap admin@demo-acme.com
    bootstrap_before = read_admin_credentials_json()
    assert bootstrap_before["email"] == "admin@demo-acme.com"
    
    # 2. New admin signup + magic claim
    new_email = "newadmin@demo-acme.com"
    client.post("/auth/signup", json={"email": new_email, "tenant_slug": "demo-acme", "password": "Pass2026!"})
    # Get token from response or DB, claim it
    client.get(f"/auth/magic?token={token}")
    
    # 3. Bootstrap admin must be UNCHANGED
    bootstrap_after = read_admin_credentials_json()
    assert bootstrap_after["email"] == "admin@demo-acme.com"  # not overwritten
    assert bootstrap_after["source"] == "setup_wizard"
    
    # 4. Both admins should be able to login
    r1 = client.post("/auth/login", json={"email": "admin@demo-acme.com", "password": "DemoPass2026!"})
    assert r1.status_code == 200
    r2 = client.post("/auth/login", json={"email": new_email, "password": "Pass2026!"})
    assert r2.status_code == 200
```

### Verify
```
# Setup state with bootstrap admin
docker exec infra-backend-1 cat /app/data/admin_credentials.json | head -3
# email=admin@demo-acme.com source=setup_wizard

# Signup new admin + claim
curl -sk -X POST http://localhost:8000/auth/signup -d '{"email":"new@digisfer.local","tenant_slug":"demo-acme","password":"Pass2026!"}'
# get magic_link from response
curl -sk -b /tmp/c.txt http://localhost:8000/auth/magic?token=...

# Re-check bootstrap
docker exec infra-backend-1 cat /app/data/admin_credentials.json | head -3
# email STILL admin@demo-acme.com source=setup_wizard (NOT overwritten)

# Both admins login
curl -sk -X POST http://localhost:8000/auth/login -d '{"email":"admin@demo-acme.com","password":"DemoPass2026!"}'  # 200
curl -sk -X POST http://localhost:8000/auth/login -d '{"email":"new@digisfer.local","password":"Pass2026!"}'  # 200
```

## 2. Round döngüsü

1. R1 = R5 git commit (Bölüm 0)
2. R2 = Bug-12 fix (auth.py:511 if-bootstrap-only)
3. Pytest 1790 → ≥1791 (1 yeni test)
4. Image rebuild + curl verify
5. Founder Phase C re-run → bootstrap admin kalır

## 3. Yasaklar

- Selective subset rapor → FULL CLEAN sayma
- Image rebuild gate
- Functionally works ≠ git committed (Round 2+5 tekrarı YASAK)
- Pilot/market gündem dışı
- L21 + Mutmut + DR actual: founder approval yok

## 4. Delegation %70+ MCP

- auth.py guard logic: ask_gptoss
- Test fixtures bootstrap + claim: write_tests
- Patch judge: judge_patch

## 5. Başarı kriteri

- admin_credentials.json claim sonrası UNCHANGED
- Bootstrap admin login devam ediyor
- New admin User tablosundan login (cookie session)
- Backend pytest 1790 → ≥1791
- Image rebuild + live verify
- R5 + R6 commit'lenmiş

## 6. Evidence

- /tmp/founder_final_big_v2.json (13/14 PASS, install script bug + tenant verify curl PASS)
- auth.py:511 root cause
- Founder reset script (docker exec python3 bcrypt) bug-12 reproduce ediyor

## 7. Devam komutu

```
cd /Users/eneseserkan/Main/abs-server-product
git status --short
git log --oneline -5
cat _agent-tasks/WORKER_FOUNDER_TEST_FIX_6.md
docker exec infra-backend-1 cat /app/data/admin_credentials.json
```

Engelleyici YOK. Bu round sonrası tester teslimat eşik son MÜHÜR — final big test 14/14 + bootstrap admin protection.
