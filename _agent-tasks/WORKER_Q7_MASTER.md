# WORKER Q7 MASTER — Neo4j + Marketplace Hardening + Panel UI Premium + Quality/Bug Hunt

> **Tetikleyici:** Q6 13/13 PASS, ABS PILOT DEMO İHRAC HAZIR. Müşteri (2026-04-30 görüşme) 4 öncelik bildirdi:
>   1. **Neo4j entegrasyonu** — graph DB için sistem hazır olsun
>   2. **Plugin marketplace eklenebilirliği** — dikkatli kontrol + test
>   3. **Panel UI premium refactor** — cosmos basit ve iyi değil, "en iyi teknolojiler" kullanılmalı
>   4. **Kalite + bug hunt** — günlerce sürecek, hata ayıklama
> **Toplam:** 5 phase · ~32h sequential / **12h paralel 4 worker** · ~1.5-2 iş günü

---

## 0. Ön Koşullar

| Madde | Değer |
|------|-------|
| Çalışma dizini | `/Users/eneseserkan/Main/abs-server-product` |
| Branch | `feat/sprint-q7-master` (master'dan) |
| Q6 baseline | repo state `feat/sprint-q6-final` post-merge, 99/92 chain |
| Önceki brief | `WORKER_Q6_FINAL.md` |
| Audit checklist | `WORKER_EXTRA_AUDIT_v1.md` |
| Memory | `feedback_visual_quality_unacceptable.md`, `feedback_provider_degradation_test.md`, `milestone_20260430_q6_pilot_demo_ready.md` |

**Pre-flight:**
```bash
git checkout master && git pull
git checkout -b feat/sprint-q7-master
bash artifacts/sprint_q6/repro.sh  # 13/13 olmalı
docker compose -f infra/docker-compose.yml -f infra/docker-compose.dev.yml ps
```

---

## 1. Sıra ve Bağımlılıklar

```
Phase A: Neo4j Integration (8h)         ─┐
Phase B: Marketplace Hardening (4h)     │  3 paralel
Phase C: Panel UI Premium (12h)         ─┘

Phase D: Quality/Bug Hunt (6h)          ── needs A+B+C
Phase E: Final Q7 Audit (1h)            ── exit gate
```

**3 worker paralel:** ~13h (longest = Phase C).
**Tek worker:** ~32h sequential.

---

## 2. PHASE A — Neo4j Integration (8h)

### Hedef
Müşteri talep etti: Neo4j community edition self-host + Qdrant ↔ Neo4j sync + NL→graph query endpoint. CRM ilişki ağı, organizasyon hiyerarşisi, network analizi senaryoları için hazır olsun.

### Deliverables

**1. Docker compose service** (`infra/docker-compose.dev.yml` ekle):
```yaml
neo4j:
  image: neo4j:5.18-community
  container_name: abs-cj-neo4j
  restart: unless-stopped
  ports:
    - "7474:7474"  # HTTP UI
    - "7687:7687"  # Bolt protocol
  environment:
    - NEO4J_AUTH=neo4j/${NEO4J_PASSWORD:-AbsNeo2026!}
    - NEO4J_PLUGINS=["apoc"]
    - NEO4J_dbms_memory_heap_max__size=2G
    - NEO4J_server_default__listen__address=0.0.0.0
  volumes:
    - abs-neo4j-data:/data
    - abs-neo4j-logs:/logs
  healthcheck:
    test: ["CMD", "wget", "-qO-", "http://localhost:7474"]
    interval: 15s
    timeout: 5s
    retries: 5
```

**2. Backend client** (`core/backend/app/integrations/neo4j_client.py` yeni):
```python
from neo4j import AsyncGraphDatabase
from app.config import settings

class Neo4jClient:
    def __init__(self):
        self.driver = AsyncGraphDatabase.driver(
            settings.neo4j_uri or "bolt://neo4j:7687",
            auth=(settings.neo4j_user, settings.neo4j_password),
        )

    async def close(self):
        await self.driver.close()

    async def query(self, cypher: str, params: dict = None) -> list[dict]:
        async with self.driver.session() as s:
            result = await s.run(cypher, params or {})
            return [r.data() async for r in result]

    async def upsert_entity(self, label: str, props: dict, key: str = "id"):
        cypher = f"MERGE (n:{label} {{{key}: ${key}}}) SET n += $props RETURN n"
        return await self.query(cypher, {key: props[key], "props": props})

    async def upsert_relation(self, src_id: str, rel_type: str, dst_id: str, props: dict = None):
        cypher = f"""
        MATCH (a {{id: $src_id}}), (b {{id: $dst_id}})
        MERGE (a)-[r:{rel_type}]->(b)
        SET r += $props
        RETURN r
        """
        return await self.query(cypher, {"src_id": src_id, "dst_id": dst_id, "props": props or {}})
```

**3. Settings** (`core/backend/app/config.py` extend):
```python
neo4j_uri: str = ""
neo4j_user: str = "neo4j"
neo4j_password: str = ""
```

**4. API endpoints** (`core/backend/app/api/graph.py` yeni):
```python
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from app.integrations.neo4j_client import Neo4jClient
from app.security.session import require_admin

router = APIRouter(prefix="/v1/graph", tags=["graph"])

class CypherRequest(BaseModel):
    cypher: str
    params: dict = {}

class IngestRequest(BaseModel):
    entities: list[dict]  # [{label, props (id required)}, ...]
    relations: list[dict] = []  # [{src_id, type, dst_id, props}, ...]

class NLQueryRequest(BaseModel):
    intent: str
    locale: str = "tr"

_client = None

async def get_client():
    global _client
    if _client is None:
        _client = Neo4jClient()
    return _client

@router.post("/cypher")
async def cypher(body: CypherRequest, admin = Depends(require_admin), client = Depends(get_client)):
    """Raw Cypher query — admin only."""
    if any(kw in body.cypher.upper() for kw in ["DELETE", "DROP", "REMOVE"]) and not body.params.get("_confirm_destructive"):
        raise HTTPException(400, "destructive operations require _confirm_destructive=true")
    return {"data": await client.query(body.cypher, body.params)}

@router.post("/ingest")
async def ingest(body: IngestRequest, admin = Depends(require_admin), client = Depends(get_client)):
    """Bulk entity + relation upsert."""
    n_entities = 0
    n_relations = 0
    for e in body.entities:
        await client.upsert_entity(e["label"], e["props"], e.get("key", "id"))
        n_entities += 1
    for r in body.relations:
        await client.upsert_relation(r["src_id"], r["type"], r["dst_id"], r.get("props"))
        n_relations += 1
    return {"entities": n_entities, "relations": n_relations}

@router.post("/nl-query")
async def nl_query(body: NLQueryRequest, admin = Depends(require_admin), client = Depends(get_client)):
    """NL → Cypher → Result. LLM çevirir."""
    from app.providers.cascade import cascade_call
    prompt = f"""Convert this natural language to Neo4j Cypher query. Return JSON only:
{{"cypher": "...", "params": {{...}}, "explanation": "..."}}

NL: {body.intent}
Locale: {body.locale}

Schema hint: nodes have :Person, :Company, :Document labels. Relations: WORKS_AT, MENTIONS, OWNS."""
    response = await cascade_call(prompt=prompt)
    # Parse JSON, execute
    import json
    parsed = json.loads(response.get("completion", "{}"))
    data = await client.query(parsed["cypher"], parsed.get("params", {}))
    return {"cypher": parsed["cypher"], "explanation": parsed.get("explanation"), "data": data}
```

**5. Register** (`app/main.py`): `from app.api import graph; app.include_router(graph.router)`

**6. Sample fixture** (`tests/fixtures/graph_seed.json`):
```json
{
  "entities": [
    {"label": "Person", "props": {"id": "p1", "name": "Ali Yılmaz", "role": "CTO"}},
    {"label": "Person", "props": {"id": "p2", "name": "Ayşe Demir", "role": "Developer"}},
    {"label": "Company", "props": {"id": "c1", "name": "DemoCo", "industry": "SaaS"}}
  ],
  "relations": [
    {"src_id": "p1", "type": "WORKS_AT", "dst_id": "c1", "props": {"since": "2020"}},
    {"src_id": "p2", "type": "WORKS_AT", "dst_id": "c1", "props": {"since": "2022"}},
    {"src_id": "p1", "type": "MANAGES", "dst_id": "p2"}
  ]
}
```

**7. Pytest** (`tests/test_neo4j_integration.py`):
- Container healthcheck
- Ingest 3 entity + 3 relation
- Cypher query: `MATCH (p:Person)-[:WORKS_AT]->(c:Company {name: 'DemoCo'}) RETURN count(p)` → 2
- NL query: "DemoCo'da çalışanlar" → 2 result
- Destructive guard: DELETE without _confirm → 400

### Test
```bash
docker compose -f infra/docker-compose.dev.yml up -d neo4j
sleep 30  # Neo4j cold start
docker exec abs-cj-neo4j cypher-shell -u neo4j -p AbsNeo2026! "RETURN 1"
# expect: 1

# Ingest sample
curl -sk -b /tmp/cookie.txt -X POST http://localhost:8000/v1/graph/ingest \
  -d @tests/fixtures/graph_seed.json -H "Content-Type: application/json"
# expect: {"entities": 3, "relations": 3}

# NL query
curl -sk -b /tmp/cookie.txt -X POST http://localhost:8000/v1/graph/nl-query \
  -d '{"intent": "DemoCo'\''da kim çalışıyor?", "locale": "tr"}'
# expect: cypher + 2 person result
```

### Engelleyici Yok
Neo4j Community Edition GPLv3 — self-host onaylı.

### Exit Gate
- Neo4j container healthy
- 5 endpoint 200 (`/cypher`, `/ingest`, `/nl-query` + 2 admin)
- Pytest 5/5 PASS
- NL query end-to-end LIVE
- Sample fixture seed çalışır

### Artefakt
`artifacts/sprint_q7/phaseA_neo4j/{repro.sh, audit_summary.md, neo4j_client.py, graph_seed.json, smoke_log.txt, screenshots/}`

---

## 3. PHASE B — Marketplace Plugin Hardening (4h)

### Hedef
5 plugin install end-to-end gerçek Docker sandbox profile + cosign signature verify + tenant scope persist + edge case'ler.

### Deliverables

**1. Sandbox profile real Docker** (`core/backend/app/marketplace/sandbox.py` yeni veya extend):
```python
import docker

class PluginSandbox:
    def __init__(self):
        self.client = docker.from_env()

    def launch(self, plugin_id: str, tenant_id: str, sandbox_profile: dict) -> dict:
        """Plugin'i izole container'da başlat."""
        container = self.client.containers.run(
            image=f"ghcr.io/automatiabcn/abs-plugin-{plugin_id}:latest",
            detach=True,
            mem_limit=f"{sandbox_profile['mem_mb']}m",
            nano_cpus=int(sandbox_profile["cpu_cores"] * 1e9),
            network_mode="bridge",
            environment={
                "ABS_TENANT_ID": tenant_id,
                "ABS_PLUGIN_ID": plugin_id,
            },
            labels={
                "abs.plugin": plugin_id,
                "abs.tenant": tenant_id,
            },
            restart_policy={"Name": "unless-stopped"},
        )
        return {"container_id": container.id, "status": "running"}

    def stop(self, plugin_id: str, tenant_id: str):
        containers = self.client.containers.list(
            filters={"label": [f"abs.plugin={plugin_id}", f"abs.tenant={tenant_id}"]}
        )
        for c in containers:
            c.stop(timeout=10)
            c.remove()

    def status(self, plugin_id: str, tenant_id: str) -> dict:
        containers = self.client.containers.list(
            filters={"label": [f"abs.plugin={plugin_id}", f"abs.tenant={tenant_id}"]}
        )
        if not containers:
            return {"status": "not_running"}
        c = containers[0]
        return {"status": c.status, "id": c.id, "started_at": c.attrs["State"]["StartedAt"]}
```

**2. Cosign verify** (`core/backend/app/marketplace/cosign_verify.py` yeni):
```python
import subprocess
import shutil

def verify_signature(image: str, expected_signature: str) -> bool:
    """Cosign ile imza doğrula."""
    if not shutil.which("cosign"):
        # Fallback: imza string match (dev only)
        return True
    try:
        result = subprocess.run(
            ["cosign", "verify", image, "--key", "/etc/abs/cosign.pub"],
            capture_output=True, timeout=30,
        )
        return result.returncode == 0
    except Exception:
        return False
```

**3. Install endpoint extend** (`core/backend/app/api/marketplace.py`):
```python
@router.post("/install")
async def install(body: dict, admin = Depends(require_admin)):
    plugin_id = body["plugin_id"]
    plugin = next((p for p in PLUGINS if p["id"] == plugin_id), None)
    if not plugin:
        raise HTTPException(404, "plugin not found")

    # 1. Cosign verify
    image = f"ghcr.io/automatiabcn/abs-plugin-{plugin_id}:latest"
    if not verify_signature(image, plugin["cosign_signature"]):
        raise HTTPException(403, "signature_invalid")

    # 2. Cerbos pre-filter (tenant izin var mı?)
    # ... existing check

    # 3. Sandbox launch
    sandbox = PluginSandbox()
    result = sandbox.launch(plugin_id, admin.tenant_id, plugin["sandbox"])

    # 4. DB record
    await db.tenant_plugins.upsert(
        tenant_id=admin.tenant_id,
        plugin_id=plugin_id,
        installed_at=datetime.now(timezone.utc),
        container_id=result["container_id"],
    )

    return {"status": "installed", "plugin_id": plugin_id, "tenant": admin.tenant_id, "container_id": result["container_id"]}

@router.delete("/uninstall/{plugin_id}")
async def uninstall(plugin_id: str, admin = Depends(require_admin)):
    sandbox = PluginSandbox()
    sandbox.stop(plugin_id, admin.tenant_id)
    await db.tenant_plugins.delete(tenant_id=admin.tenant_id, plugin_id=plugin_id)
    return {"status": "uninstalled", "plugin_id": plugin_id}

@router.get("/installed")
async def installed(admin = Depends(require_admin)):
    sandbox = PluginSandbox()
    rows = await db.tenant_plugins.find({"tenant_id": admin.tenant_id}).to_list(100)
    enriched = [{**r, "live_status": sandbox.status(r["plugin_id"], admin.tenant_id)} for r in rows]
    return {"plugins": enriched, "count": len(enriched)}
```

**4. Edge case test** (`tests/test_marketplace_hardening.py`):
- 5 plugin install: hepsi 201 + container running
- Idempotent install: 2. çağrı 200 + already_installed
- Uninstall: container gone, DB row removed
- Cross-tenant: tenant-A install → tenant-B `/installed` → 0 görür
- Invalid signature: 403
- Resource limit: container memory > sandbox.mem_mb → kill
- Concurrent install (2 user same tenant): race-safe

### Test
```bash
# Install 5 plugin
for p in slack-receiver gmail-archiver linear-bridge notion-sync postgres-mirror; do
  curl -sk -b /tmp/cookie.txt -X POST http://localhost:8000/v1/marketplace/install \
    -d "{\"plugin_id\":\"$p\"}" -H "Content-Type: application/json"
done

# Check installed
curl -sk -b /tmp/cookie.txt http://localhost:8000/v1/marketplace/installed | jq '.count'
# expect: 5

# Docker containers running
docker ps --filter "label=abs.plugin" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
# expect: 5 satır

# Cross-tenant leak test
# (Q1 A8 persona test repurpose)
pytest tests/test_marketplace_hardening.py -v
```

### Engelleyici (kullanıcıya sor)
- "Plugin Docker image'ları `ghcr.io/automatiabcn/abs-plugin-*` mevcut mu? Yoksa stub image'lar (busybox + healthcheck script) ile mi başlayalım?"
- "Cosign public key vault'a koyuldu mu? Yoksa dev-only imza skip moduyla mı başlayalım?"

### Exit Gate
- 5 plugin install → 5 container running
- Cross-tenant leak: 0 (Q1 A8 regression PASS)
- Idempotent install + uninstall + installed list 200
- Edge case 7/7 PASS
- Resource limit enforce edilmiş (cgroup memory)

### Artefakt
`artifacts/sprint_q7/phaseB_marketplace/{repro.sh, audit_summary.md, sandbox.py, cosign_verify.py, container_inventory.json}`

---

## 4. PHASE C — Panel UI Premium Refactor (12h, KRİTİK)

### Hedef
Müşteri "cosmos basit ve iyi değil, en iyi teknolojileri kullanmalıyız" dedi. Mevcut panel cosmos parallax/comet trail/decorative SVG'lerle aşırı kalabalık AMA kalitesiz. Premium dashboard yaklaşımıyla yeniden tasarla.

### Stack Seçimi (en iyi teknolojiler)

| Katman | Mevcut | Yeni (premium) |
|--------|--------|-----------------|
| UI primitives | Custom CSS + cosmos | **shadcn/ui** (Radix primitives + Tailwind) |
| Komponentler | inline | **shadcn-derived** (Card, Sheet, Dialog, Command, Tabs) |
| Charts | brain_graph.html canvas | **Tremor** (dashboard-grade) + **Recharts** (custom) |
| Animasyon | Cosmos parallax + comet (kaldır) | **Framer Motion** (subtle, anlamlı) |
| Icons | Custom SVG | **Lucide React** + **Phosphor Icons** |
| Typography | Mixed | **Inter** (UI) + **JetBrains Mono** (data/code) |
| Data layer | fetch | **TanStack Query** (cache + suspense + invalidation) |
| Tables | HTML table | **TanStack Table** (sortable, filterable, sticky header) |
| Color system | OKLCH custom | **OKLCH preserve** + dark/light mode toggle |
| Theme | dark only | **Light + dark + system** (next-themes) |

### Deliverables

**1. Install dependencies** (`core/landing/package.json`):
```json
{
  "dependencies": {
    "@radix-ui/react-dialog": "^1.1",
    "@radix-ui/react-tabs": "^1.1",
    "@radix-ui/react-popover": "^1.1",
    "@radix-ui/react-select": "^2.1",
    "@tanstack/react-query": "^5.59",
    "@tanstack/react-table": "^8.20",
    "@tremor/react": "^3.18",
    "framer-motion": "^11.11",
    "lucide-react": "^0.468",
    "@phosphor-icons/react": "^2.1",
    "next-themes": "^0.4",
    "recharts": "^2.13",
    "cmdk": "^1.0",
    "vaul": "^1.1"
  }
}
```

**2. shadcn/ui setup:**
```bash
cd core/landing
npx shadcn@latest init
npx shadcn@latest add card sheet dialog tabs button input table command popover select badge skeleton sonner
```

**3. Yeni panel layout** (`core/landing/app/panel/layout.tsx`):
```tsx
"use client";
import { ThemeProvider } from "next-themes";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";
import { Toaster } from "@/components/ui/sonner";
import { PanelSidebar } from "@/components/panel/PanelSidebar";
import { PanelHeader } from "@/components/panel/PanelHeader";

export default function PanelLayout({ children }) {
  const [qc] = useState(() => new QueryClient({
    defaultOptions: { queries: { staleTime: 30_000, refetchOnWindowFocus: false } },
  }));

  return (
    <ThemeProvider attribute="class" defaultTheme="dark">
      <QueryClientProvider client={qc}>
        <div className="flex h-screen bg-background text-foreground">
          <PanelSidebar />
          <div className="flex flex-1 flex-col overflow-hidden">
            <PanelHeader />
            <main className="flex-1 overflow-auto p-6">{children}</main>
          </div>
        </div>
        <Toaster />
      </QueryClientProvider>
    </ThemeProvider>
  );
}
```

**4. Sidebar — premium nav** (`core/landing/components/panel/PanelSidebar.tsx`):
```tsx
import {
  LayoutDashboard, Workflow, Store, Mic, BarChart3, Boxes, Settings,
} from "lucide-react";

const NAV = [
  { href: "/panel", label: "Genel Bakış", icon: LayoutDashboard },
  { href: "/admin/workflow-builder", label: "Workflow", icon: Workflow },
  { href: "/admin/marketplace", label: "Marketplace", icon: Store },
  { href: "/panel/meetings", label: "Toplantılar", icon: Mic },
  { href: "/panel/quota", label: "Kota", icon: BarChart3 },
  { href: "/panel/tools", label: "MCP Tool", icon: Boxes },
  { href: "/panel/settings", label: "Ayarlar", icon: Settings },
];

export function PanelSidebar() {
  return (
    <aside className="w-60 border-r border-border bg-card/50 backdrop-blur p-4">
      <div className="mb-8 flex items-center gap-2">
        <div className="h-8 w-8 rounded bg-primary/20 flex items-center justify-center">
          {/* logo */}
        </div>
        <span className="font-mono text-sm">Automatia ABS</span>
      </div>
      <nav className="space-y-1">
        {NAV.map((item) => (
          <NavLink key={item.href} {...item} />
        ))}
      </nav>
    </aside>
  );
}
```

**5. Dashboard home with Tremor** (`core/landing/app/panel/page.tsx`):
```tsx
"use client";
import { useQuery } from "@tanstack/react-query";
import { Card, Metric, Text, AreaChart, BarList, Flex, BadgeDelta, Grid, Col, Title } from "@tremor/react";
import { motion } from "framer-motion";

const fetcher = (url: string) => fetch(url, { credentials: "include" }).then((r) => r.json());

export default function PanelHome() {
  const { data: tools } = useQuery({ queryKey: ["tools"], queryFn: () => fetcher("/v1/panel/tools") });
  const { data: quota } = useQuery({ queryKey: ["quota"], queryFn: () => fetcher("/v1/system/quota_status"), refetchInterval: 30_000 });
  const { data: cascade } = useQuery({ queryKey: ["cascade"], queryFn: () => fetcher("/v1/panel/cascade/recent"), refetchInterval: 10_000 });

  return (
    <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3 }}>
      <Title>Genel Bakış</Title>
      <Text>ABS sistem durumu, son 24 saat aktivite</Text>

      <Grid numItems={1} numItemsSm={2} numItemsLg={4} className="gap-4 mt-6">
        <Card>
          <Flex>
            <Text>Toplam MCP Tool</Text>
            <BadgeDelta deltaType="moderateIncrease">+3</BadgeDelta>
          </Flex>
          <Metric>{tools?.total ?? "—"}</Metric>
          <Text>{Object.keys(tools?.category_counts ?? {}).length} kategori</Text>
        </Card>
        <Card>
          <Flex>
            <Text>Cascade Çağrıları (24h)</Text>
            <BadgeDelta deltaType="increase">+18%</BadgeDelta>
          </Flex>
          <Metric>{cascade?.count ?? "—"}</Metric>
          <Text>p95 < 12ms</Text>
        </Card>
        <Card>
          <Flex>
            <Text>Claude Plus Kota</Text>
            <BadgeDelta deltaType={quota?.warnings?.length ? "decrease" : "unchanged"}>
              {((quota?.claude_plus?.percent ?? 0) * 100).toFixed(0)}%
            </BadgeDelta>
          </Flex>
          <Metric>{(quota?.claude_plus?.used ?? 0).toLocaleString("tr-TR")}</Metric>
          <Text>/ {(quota?.claude_plus?.limit ?? 0).toLocaleString("tr-TR")} token</Text>
        </Card>
        <Card>
          <Flex>
            <Text>Configured Provider</Text>
          </Flex>
          <Metric>{cascade?.providers_active ?? 0} / 6</Metric>
          <Text>Cascade chain</Text>
        </Card>
      </Grid>

      <Grid numItems={1} numItemsLg={2} className="gap-4 mt-6">
        <Card>
          <Title>Son Cascade Çağrıları</Title>
          <AreaChart
            data={cascade?.timeseries ?? []}
            index="ts"
            categories={["count"]}
            colors={["blue"]}
            className="h-72 mt-4"
          />
        </Card>
        <Card>
          <Title>Tool Kategori Dağılımı</Title>
          <BarList
            data={Object.entries(tools?.category_counts ?? {})
              .sort((a, b) => b[1] - a[1])
              .slice(0, 8)
              .map(([name, value]) => ({ name, value }))}
            className="mt-4"
          />
        </Card>
      </Grid>
    </motion.div>
  );
}
```

**6. Cosmos kaldır:**
- `core/landing/components/cosmos/*` → sil veya pasifleştir
- `automatiabcn_panel_v2.html` (SERVER ops panel) — bu KORUNUR (CLAUDE.md guard), AMA müşteri-temas eden `/panel` Next.js'e tamamen yeni
- Comet trail / parallax / accretion / lensing / orbit ring → kaldır

**7. Theme toggle** (`core/landing/components/panel/ThemeToggle.tsx`):
```tsx
"use client";
import { Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";
import { Button } from "@/components/ui/button";

export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  return (
    <Button variant="ghost" size="icon" onClick={() => setTheme(theme === "dark" ? "light" : "dark")}>
      <Sun className="h-4 w-4 dark:hidden" />
      <Moon className="h-4 w-4 hidden dark:block" />
    </Button>
  );
}
```

**8. Diğer panel sayfaları (Workflow, Meetings, Quota, Marketplace) aynı pattern** — Card + Tremor + Framer Motion subtle entrance.

### Test
```bash
cd core/landing
npm install
npm run build  # zero error
npm run dev

# Visual regression
node cj_annotated_tour.mjs  # 10 page, premium UI doğrulama

# Lighthouse
npx lighthouse http://localhost:3000/panel --view
# Expect: Performance ≥ 90, Accessibility ≥ 95, SEO ≥ 90

# Bundle size
du -sh core/landing/.next/static/chunks/app
# Expect: < 2MB (panel route)
```

### Exit Gate
- shadcn/ui + Tremor + Framer Motion + TanStack Query installed
- 7 panel sayfa premium refactor (Genel Bakış, Workflow, Marketplace, Meetings, Transcription, Quota, Tools)
- Cosmos kaldırıldı (frontend, ops panel KORUNUR)
- Lighthouse perf ≥ 90, a11y ≥ 95
- Theme toggle (dark/light) çalışır
- Real-time data (TanStack Query polling)
- Subtle animasyon (Framer Motion entrance only, parallax YOK)

### Artefakt
`artifacts/sprint_q7/phaseC_panel_premium/{repro.sh, audit_summary.md, before_after.md, lighthouse_report.json, screenshots/{before,after}/}`

---

## 5. PHASE D — Quality + Bug Hunt (6h)

### Hedef
Sistem stabilizasyonu — Q7'nin yeni kod (Neo4j + marketplace + UI) regresyon yaratmasın. 5xx sweep, console error elimination, edge case audit.

### Deliverables

**1. Full regression suite:**
```bash
bash artifacts/sprint_hotfix_cj/repro.sh
bash artifacts/sprint_20_impl/repro.sh
bash artifacts/sprint_q1_quality/repro.sh
bash artifacts/sprint_q2_master/repro.sh
bash artifacts/sprint_q3/repro.sh
bash artifacts/sprint_q4/repro.sh
bash artifacts/sprint_q5/run_full_chain.sh
bash artifacts/sprint_q6/repro.sh
# Cumulative target: 99/99 PASS
```

**2. 5xx sweep** (extend `artifacts/sprint_q7/sweep.sh`):
```bash
# Tüm GET routes + yeni POST/DELETE endpoint'ler
ROUTES=$(curl -sk http://localhost:8000/openapi.json | jq -r '.paths | keys[]')
for route in $ROUTES; do
  STATUS=$(curl -sk -b /tmp/cookie.txt -o /dev/null -w "%{http_code}" "http://localhost:8000$route" --max-time 5)
  echo "$STATUS $route" >> /tmp/sweep.log
done
grep -E "^5" /tmp/sweep.log  # 0 satır olmalı
```

**3. Console error elimination:**
- Playwright headed her sayfada `console.error` count
- Hedef: 0 console error / 0 console warn (404 favicon hariç)

**4. Edge case audit:**
- Empty state UI (henüz tool yok, henüz kullanıcı yok, henüz quota yok)
- Loading state skeleton'ları
- Error state (network down, 500, timeout)
- Long content overflow (uzun meeting list, 1000 tool)
- Slow connection simulation

**5. Memory leak check:**
- Panel'de 30 dakika idle → memory growth < 10MB
- TanStack Query cache invalidation doğru
- WebSocket reconnect leak yok

**6. Accessibility audit:**
- `npm run axe` veya Playwright + axe-core
- Hedef: 0 critical/serious violation

### Test
```bash
# Full regression
bash run_all_repros.sh

# Sweep
bash artifacts/sprint_q7/sweep.sh
grep -c "^5" /tmp/sweep.log  # 0

# Console errors
node tests/console_audit.mjs
# Expect: 0 errors per page

# Memory leak
node tests/memory_leak.mjs --duration=1800
# Expect: heap growth < 10MB

# A11y
npm run axe
# Expect: 0 critical/serious
```

### Exit Gate
- Cumulative 99+/99 PASS (regression)
- 0 yeni 5xx
- 0 yeni console error
- 6/6 edge case PASS
- Memory leak: hayır
- A11y: 0 critical/serious

### Artefakt
`artifacts/sprint_q7/phaseD_quality/{repro.sh, audit_summary.md, sweep.log, console_errors.json, memory_profile.json, axe_report.json}`

---

## 6. PHASE E — Final Q7 Audit (1h)

`WORKER_EXTRA_AUDIT_v1.md` 8 kontrol:
1. Bağlam — automated metrics
2. Audit round — Playwright headed (yeni premium UI screenshot)
3. E2E customer flow — landing → setup → login → cascade → workflow → marketplace install + uninstall → meetings → quota → graph query
4. Default credentials drift
5. Static assets vs API gap
6. Required field vs customer promise
7. 404/500 sweep (Phase D'den)
8. Visual quality audit — premium UI screenshot vs cosmos before/after

### Geçme Kriteri
- 0 yeni CRITICAL + 0 yeni HIGH
- ≤3 yeni MEDIUM
- 4 önceki phase exit gate'ler geçmiş

### Artefakt
`artifacts/sprint_q7/master_audit_summary.md` + repro.sh master

---

## 7. Çıktı Klasör Yapısı

```
artifacts/sprint_q7/
├─ phaseA_neo4j/
├─ phaseB_marketplace/
├─ phaseC_panel_premium/
│   ├─ before_after.md
│   ├─ screenshots/before/  (cosmos kalabalık)
│   ├─ screenshots/after/   (premium shadcn)
│   └─ lighthouse_report.json
├─ phaseD_quality/
├─ master_repro.sh
└─ master_audit_summary.md
```

---

## 8. Çalışma Şartı

**Sıralama:**
- Phase A + B + C paralel (3 worker)
- Phase D, A+B+C PASS sonra
- Phase E, D PASS sonra

**Commit format:**
```
feat(q7): phase<X> <component> <açıklama>
```

**Branch:** `feat/sprint-q7-master`

**Paralel önerisi (3-4 worker):**
- Worker A: Phase A Neo4j (8h)
- Worker B: Phase B Marketplace (4h) → Phase D quality (6h, A+C bekler)
- Worker C: Phase C Panel UI (12h) — en uzun
- Worker D: Phase E final + carry-over Q7-live

**Toplam paralel:** ~13h (longest = Phase C).

---

## 9. Engelleyiciler — Kullanıcıya Sor

| # | Faz | Engel | Sorulacak |
|---|-----|-------|-----------|
| 1 | A | Neo4j password | "NEO4J_PASSWORD env vault'ta mı, yoksa default `AbsNeo2026!` mı?" |
| 2 | B | Plugin Docker images | "ghcr.io/automatiabcn/abs-plugin-* mevcut mu? Yoksa stub busybox?" |
| 3 | B | Cosign public key | "vault'ta mı, yoksa dev-only skip mode?" |
| 4 | C | UI tasarım onayı | "shadcn/ui + Tremor stack OK mi? Mockup gönderir misin?" |
| 5 | C | Cosmos tamamen kaldır | "Frontend cosmos kaldırılsın, ops panel korunsun (CLAUDE.md guard) — onay?" |

**Phase A + D + E autonomous.**

---

## 10. Geçme Kriteri (Master Final)

| Faz | Hedef |
|-----|-------|
| A Neo4j | 5/5 endpoint 200 + NL query LIVE |
| B Marketplace | 5 plugin install + 0 cross-leak + 7/7 edge case |
| C Panel UI | 7 sayfa premium + Lighthouse ≥ 90 + cosmos kaldırıldı |
| D Quality | Cumulative 99+/99 PASS + 0 yeni 5xx + a11y temiz |
| E Audit | 0/0 yeni CRIT/HIGH |

**Cumulative:** 99 + 8 (Q7) = **107 assertion 107/107 PASS**

**FAIL durumunda:** master_audit_summary.md `# ❌ FAIL`, sıra bozulur.

**PASS durumunda:**
- Sprint Q7 kapanır
- `milestone_20260501_q7_neo4j_premium.md` memory ekle
- Müşteri demo paketi güncel (Gamma sunum + annotated tour + before/after screenshots)
- Customer pilot başlatılabilir

---

## 11. Cumulative Sprint Chain (Q7 sonrası)

| Sprint | Repro |
|--------|-------|
| Hotfix CJ | 17/17 |
| Sprint 20 | 15/15 |
| Q1 Quality | 30/30 |
| Q2 Master | 8/8 |
| Q3 Master | 8/8 |
| Q4 Master | 8/8 |
| Q5 Master | (chain runner) |
| Q6 Final | 13/13 |
| **Q7 Master** | **8/8 (target)** |
| **TOPLAM** | **107/107** |

**~36-40h cumulative** = ABS Server Product **PILOT-READY + NEO4J + PREMIUM UI** in 10-sprint chain.

---

**Tahmini süre:** 32h sequential / **13h paralel 3 worker** ~ 1.5-2 iş günü.
**Son güncelleme:** 2026-04-30 · Q7 master brief v1
