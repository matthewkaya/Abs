# Phase Q9.A — Customer Journey Live Run

**Status:** Founder hand-off — interactive Claude Code session bir
docker compose stack + headed browser orchestration'unu güvenle yürütemez
(state hijack + uzun süre + UI focus). Test script Q8'de hazır, Q9.B-E
fix'lerinden sonra aşağıdaki adımlarla local'de koşulur.

## Pre-flight

```bash
cd /Users/eneseserkan/Main/abs-server-product
git checkout feat/sprint-q9-finalize

# 1. Image rebuild (Q7+Q8 dersi — source ship ≠ container ship)
docker compose -f infra/docker-compose.yml \
               -f infra/docker-compose.dev.yml \
               up -d --build backend caddy frontend

# 2. Backend canlı doğrulama
sleep 8
curl -sk http://localhost:8000/healthz                          # {"status":"ok"}
curl -sk http://localhost:8000/v1/chat/sessions -w "\n%{http_code}\n"  # 401 (gate çalışıyor)
docker exec infra-backend-1 ls /app/app/api/chat.py            # source container'da

# 3. Bootstrap admin login (cookie üret)
COOKIE=/tmp/q9_cookie.txt
curl -sk -c "$COOKIE" -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@local","password":"CHANGEME"}' -w "\n%{http_code}\n"
curl -sk -b "$COOKIE" http://localhost:8000/v1/chat/sessions   # 200 [...]
```

## Run

```bash
cd core/landing
ABS_PANEL_PASSWORD=CHANGEME \
  npx playwright test q8-customer-journey --headed
```

Test 11 step + screenshot her biri için
`artifacts/sprint_q9/screenshots/customer_journey_<slug>.png`'a yazar.

## Beklenen sonuç

| # | Slug | URL | Selector | Beklenen |
|---|------|-----|----------|----------|
| 1 | 01-panel-home | /panel | data-test=panel-stats | NeuralGraph + 4-tile |
| 2 | 02-panel-chat | /panel/chat | data-page=panel-chat | 3-col, sample prompts |
| 3 | 03-workflow-builder | /admin/workflow-builder | workflow-canvas-title | react-flow canvas |
| 4 | 04-tools | /panel/tools | data-page=panel-tools | TanStack table 122 row |
| 5 | 05-providers | /admin/providers | data-page=admin-providers | 6 cascade chip |
| 6 | 06-pipelines | /admin/pipelines | data-page=admin-pipelines | 9 pipeline card |
| 7 | 07-rag | /admin/rag | data-page=admin-rag | dropzone + query |
| 8 | 08-marketplace | /admin/marketplace | data-page=admin-marketplace | 10 plugin card + permission preview |
| 9 | 09-quota | /panel/quota | data-page=panel-quota | DateRangePicker + 4-tile + bars |
| 10 | 10-graph | /admin/graph | data-page=admin-graph | Cypher editor + sample queries |
| 11 | 11-settings | /admin/settings | data-page=admin-settings | 7-tab nav |

## Console-error gate

`HARMLESS = ["Stripe", "favicon", "DevTools", "next-router-mock"]`. Diğer
her console.error testi düşürür. Q9.B+C ekleri AnalyserNode ve
DateRangePicker; ikisi de SSR-safe (Waveform `useEffect` içinde, Tremor
client component).

## Hata ile karşılaşırsan

1. **401 redirect to /panel/login** — `ABS_PANEL_PASSWORD` env yok veya
   admin_credentials.json bootstrap edilmemiş. `setup` wizard'ı bir kez
   tamamla veya `.env`'e `ABS_ADMIN_PASSWORD_BOOTSTRAP=CHANGEME` ekle.
2. **404 panel/chat** — image rebuild yapılmamış demektir (Q7+Q8
   gap'i). `docker compose up -d --build backend` ve container
   içeride `ls /app/app/api/chat.py` doğrula.
3. **Console hydration warning** — next-themes mismatch olduğu
   senaryoları Q8 MT3 ile çözüldü; halen görüyorsan
   `components/panel/ThemeToggle.tsx` `mounted` state pattern'i kontrol
   et.
4. **Waveform blank canvas** — AudioContext suspended olabilir;
   Chrome'un autoplay policy mic permission acknowledgement sonrası
   resume'unu bekler. TR2 modal acknowledgement sonrası start() içinde
   AudioContext yaratılması bu sorunu düzeltir.

---

**Owner:** Founder Enes
**Pre-req:** docker compose stack up + bootstrap admin
**Çıktı:** 11 screenshot + Playwright JSON report → audit summary
