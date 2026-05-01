# WORKER Q7 FINALIZE — Production Deploy Gap Fix (30 dk acil)

> **Tetikleyici:** Q7 master 193/193 PASS shipped, ancak production deploy eksik:
>   - `/v1/graph/*` endpoint'leri canlı **404** (graph.py backend container'da yok)
>   - main.py'da `graph` router register edilmemiş
>   - `q7_bootstrap.sh` + `credential_reset.sh` host `scripts/` altında yok (kalıcı değil)
> **Hedef:** Q7 ship-it kapanışı — 30 dakikalık iş, müşteri demo'sunu blocklar
> **Branch:** `feat/sprint-q7-finalize` (`feat/sprint-q7-master` üzerine)

---

## 0. Ön Koşullar

```bash
git checkout feat/sprint-q7-master && git pull
git checkout -b feat/sprint-q7-finalize
docker compose -f infra/docker-compose.yml -f infra/docker-compose.dev.yml ps  # neo4j healthy
```

**Verification script hazır:** `scripts/q7_finalize_verify.sh` (14 check, exit 0 = PASS)

---

## 1. Sıra (Tek Worker, ~30 dk)

```
Step 1 → 2 → 3 → 4 → 5 → 6 → 7 (sequential)
```

---

## 2. Step 1 — Backend Dockerfile COPY (5 dk)

**Dosya:** `core/backend/Dockerfile`

Yeni Q7 source dosyalarını imaja al:

```dockerfile
# Q7 — Neo4j integration
COPY app/api/graph.py /app/app/api/graph.py
COPY app/integrations/neo4j_client.py /app/app/integrations/neo4j_client.py
# Q7 — Marketplace hardening
COPY app/marketplace/sandbox.py /app/app/marketplace/sandbox.py
COPY app/marketplace/cosign_verify.py /app/app/marketplace/cosign_verify.py
```

**Test:**
```bash
docker compose -f infra/docker-compose.yml build backend
docker exec abs-cj-backend-1 ls /app/app/api/graph.py /app/app/integrations/neo4j_client.py /app/app/marketplace/sandbox.py /app/app/marketplace/cosign_verify.py
# Expect: hepsi listelenmeli
```

---

## 3. Step 2 — main.py register (3 dk)

**Dosya:** `core/backend/app/main.py`

`from app.api import symbol_graph as symbol_graph_router` satırının yanına ekle:

```python
from app.api import graph as graph_router
```

`include_router` block'una ekle:

```python
app.include_router(graph_router.router)
```

**Test:**
```bash
docker exec abs-cj-backend-1 grep -E "from app.api import graph|include_router\(graph" /app/app/main.py
# Expect: 2 satır
```

---

## 4. Step 3 — docker compose rebuild (5 dk)

```bash
docker compose -f infra/docker-compose.yml -f infra/docker-compose.dev.yml up -d --build backend
sleep 8
docker logs abs-cj-backend-1 --tail 20 | grep -iE "graph|started|listening"
curl -sk -o /dev/null -w "/healthz=%{http_code}\n" http://localhost:8000/healthz
# Expect: 200
```

---

## 5. Step 4 — Host scripts kalıcılaştır (5 dk)

**Dosya:** `scripts/q7_bootstrap.sh` (yeni, executable)

Worker'ın container'a `docker cp` ile koyduğu bootstrap mantığı script'e aktarılsın:
```bash
#!/usr/bin/env bash
# Q7 backend bootstrap — image rebuild olmadan dev tarafında source güncellemesi için
set -euo pipefail
SOURCE="core/backend/app"
docker cp "$SOURCE/api/graph.py" abs-cj-backend-1:/app/app/api/graph.py
docker cp "$SOURCE/integrations/neo4j_client.py" abs-cj-backend-1:/app/app/integrations/
docker cp "$SOURCE/marketplace/sandbox.py" abs-cj-backend-1:/app/app/marketplace/
docker cp "$SOURCE/marketplace/cosign_verify.py" abs-cj-backend-1:/app/app/marketplace/
docker exec abs-cj-backend-1 sh -c 'kill -HUP 1' || docker restart abs-cj-backend-1
```

**Dosya:** `scripts/credential_reset.sh` (yeni, executable)

```bash
#!/usr/bin/env bash
# Bootstrap admin credentials reset — repro chain için known state
set -euo pipefail
docker exec abs-cj-backend-1 sh -c 'rm -f /app/data/admin_credentials.json'
docker exec abs-cj-backend-1 python -c "
import bcrypt, json, time
pw_hash = bcrypt.hashpw(b'LocalPass2026!', bcrypt.gensalt()).decode()
json.dump({'email':'admin@demo-acme.local','password_hash':pw_hash,'created_at':time.time()}, open('/app/data/admin_credentials.json','w'))
print('admin reset OK')
"
```

```bash
chmod +x scripts/q7_bootstrap.sh scripts/credential_reset.sh
git add scripts/q7_bootstrap.sh scripts/credential_reset.sh
```

---

## 6. Step 5 — Live smoke (5 dk)

```bash
# 1. Login (credential reset çalıştırdıktan sonra)
bash scripts/credential_reset.sh
COOKIE=$(curl -sk -c /tmp/q7c.txt -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@demo-acme.local","password":"LocalPass2026!"}' \
  -i 2>&1 | grep -oE "abs_session=[^;]+" | head -1)
echo "Cookie: $COOKIE"

# 2. /v1/graph endpoint'leri canlı
curl -sk -b /tmp/q7c.txt -X POST http://localhost:8000/v1/graph/ingest \
  -H "Content-Type: application/json" \
  -d '{"entities":[{"label":"Person","props":{"id":"p1","name":"Test"}}]}' \
  -w "\ningest=%{http_code}\n"
# Expect: 200

curl -sk -b /tmp/q7c.txt -X POST http://localhost:8000/v1/graph/cypher \
  -H "Content-Type: application/json" \
  -d '{"cypher":"MATCH (p:Person {id:\"p1\"}) RETURN p.name"}' \
  -w "\ncypher=%{http_code}\n"
# Expect: 200

curl -sk -b /tmp/q7c.txt -X POST http://localhost:8000/v1/graph/nl-query \
  -H "Content-Type: application/json" \
  -d '{"intent":"Test kullanıcısını bul","locale":"tr"}' \
  -w "\nnl-query=%{http_code}\n"
# Expect: 200 (or 422 if NL parse fails — also acceptable, not 404)

# 3. Marketplace install real sandbox
curl -sk -b /tmp/q7c.txt -X POST http://localhost:8000/v1/marketplace/install \
  -d '{"plugin_id":"slack-receiver"}' -H "Content-Type: application/json" \
  -w "\ninstall=%{http_code}\n"
# Expect: 200/201

docker ps --filter "label=abs.plugin" --format "{{.Names}}"
# Expect: en az 1 container running
```

---

## 7. Step 6 — master_repro.sh dış-curl-based check (5 dk)

**Dosya:** `artifacts/sprint_q7/master_repro.sh`

Mevcut Phase A repro içeriden test ediyor (in-container mock). Dışarıdan canlı curl ekle:

```bash
echo "=== Q7.A LIVE — /v1/graph/* dış curl ==="
COOKIE=$(curl -sk -c /tmp/q7c.txt -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@demo-acme.local","password":"LocalPass2026!"}' -i 2>&1 \
  | grep -oE "abs_session=[^;]+" | head -1)
[ -n "$COOKIE" ] && echo "  PASS  auth login" || echo "  FAIL  auth login"

for ep in cypher ingest nl-query; do
  CODE=$(curl -sk -b /tmp/q7c.txt -X POST "http://localhost:8000/v1/graph/$ep" \
    -d '{}' -H "Content-Type: application/json" -o /dev/null -w "%{http_code}" --max-time 5)
  if [[ "$CODE" =~ ^(200|400|422)$ ]]; then
    echo "  PASS  /v1/graph/$ep ($CODE)"
  else
    echo "  FAIL  /v1/graph/$ep = $CODE (404 olmamalı)"
  fi
done
```

---

## 8. Step 7 — master_audit_summary.md deploy verdict (2 dk)

**Dosya:** `artifacts/sprint_q7/master_audit_summary.md`

En üste ekle:

```markdown
## Production Deploy Verdict (Q7 finalize)

**Tarih:** 2026-04-30
**Durum:** ✅ DEPLOYED (was: ❌ test-only ship-it)

| Bileşen | Durum |
|---------|-------|
| graph.py + neo4j_client.py backend container | ✅ Dockerfile COPY |
| main.py graph router register | ✅ include_router |
| Image rebuild | ✅ docker compose up -d --build backend |
| host scripts/q7_bootstrap.sh | ✅ committed |
| host scripts/credential_reset.sh | ✅ committed |
| /v1/graph/cypher live | ✅ 200 |
| /v1/graph/ingest live | ✅ 200 |
| /v1/graph/nl-query live | ✅ 200/422 |
| Marketplace install real sandbox | ✅ Docker container running |
| master_repro.sh dış-curl check | ✅ added |

Production-ready: müşteri pilot demo açılabilir.
```

---

## 9. Verification (final)

```bash
bash scripts/q7_finalize_verify.sh
# Expect: PASS=14 FAIL=0
```

Eğer FAIL varsa, hangi step eksik olduğu belli olacak (script gap'leri tek tek raporlar).

---

## 10. Çıktı + Commit

```bash
git add core/backend/Dockerfile core/backend/app/main.py
git add scripts/q7_bootstrap.sh scripts/credential_reset.sh
git add artifacts/sprint_q7/master_repro.sh artifacts/sprint_q7/master_audit_summary.md
git commit -m "fix(q7): production deploy — graph router register + dockerfile + host scripts

Co-Authored-By: ABS Worker <worker@automatiabcn.local>"
```

PR'a "Q7 finalize: production deploy gap closed (193/193 → live verified)" başlığı.

---

## 11. Engelleyici Yok

Tüm 7 step **autonomous**. Soru sormaya gerek yok.

---

## 12. Geçme Kriteri

| Check | Hedef |
|-------|-------|
| `q7_finalize_verify.sh` | PASS=14 FAIL=0 |
| `master_repro.sh` | önceki 193/193 + yeni dış-curl PASS |
| Live `/v1/graph/{cypher,ingest,nl-query}` | hepsi ≠ 404 |
| Marketplace install | gerçek Docker sandbox container başlatır |
| Backend image rebuild | `abs-cj-backend-1` healthy + Q7 dosyaları içinde |

---

**Tahmini süre:** 30 dakika
**Son güncelleme:** 2026-04-30 · Q7 finalize brief v1
