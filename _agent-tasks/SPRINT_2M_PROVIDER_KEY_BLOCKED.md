# SPRINT 2M — Provider API Key Block Notice

**Date:** 2026-05-14
**Sprint:** 2M Customer E2E Audit
**Faz:** A2 (provider key inventory)
**Status:** BLOCKED — STOP CRITERIA #1 partial activation

---

## Bulgu

Brief FAZ A2 6 provider key'i `ai-pc:~/keys/` veya M4 lokal'den çekmemi istiyor. Envanter
sonucu (Lesson 13 enforce — sadece dosya isim listing, içerik echo'lanmadı):

### ai-pc:~/keys/ listing
| Dosya | Var mı | Notu |
|-------|--------|------|
| anthropic-api-key | ❌ | yok |
| groq-api-key | ❌ | yok |
| gemini-api-key | ❌ | yok |
| cerebras-api-key | ❌ | yok |
| cohere-api-key | ❌ | yok |
| openai-api-key | ❌ | yok |
| abs-cf-license-creds.txt | ✅ | CF activation creds (FAZ B license mint için) |
| abs-manifest-signing-{private,public}.pem | ✅ | manifest signing |
| github-pat-abs-v3.txt | ✅ | GHCR pull (FAZ B2 için) |
| hetzner-cloud-api-token.txt | ✅ | Hetzner API |
| resend-api-key | ✅ | transactional email |

### M4 lokal taraması
- `/Users/eneseserkan/keys/` — klasör mevcut değil
- `/Users/eneseserkan/.config/abs/` — klasör mevcut değil
- `abs-server-product/.env`, `infra/.env`, `customer-keys/pilot-customer-1/.env` — `ANTHROPIC_API_KEY` / `GROQ_API_KEY` / `GEMINI_API_KEY` / `CEREBRAS_API_KEY` / `COHERE_API_KEY` / `OPENAI_API_KEY` satırları **boş** (placeholder pattern, gerçek değer yok)

**Sonuç:** 6/6 provider key erişilemez. Auto-mode reddi DEĞIL — fiziksel olarak founder
sistemine deploy edilmemiş.

---

## Founder paste talebi

Brief FAZ D-J cascade/MCP gerçek API testleri için en az 1 provider key zorunlu (ideal: 6/6).
Founder şu satırları stdin pipe ile ya da Bash command olarak `/tmp/abs-customer-sim/.env`
dosyasına ekleyebilir:

```
ANTHROPIC_API_KEY=sk-ant-...
GROQ_API_KEY=gsk_...
GEMINI_API_KEY=AIza...
CEREBRAS_API_KEY=csk-...
COHERE_API_KEY=...
OPENAI_API_KEY=sk-...     # opsiyonel (quota tüketmemek için skip OK)
```

Founder paste mekanizması (Lesson 13 enforce — transcript echo YOK):

**Opsiyon 1 — Bash command (önerilir):**
```
cd /tmp/abs-customer-sim
read -s -p "ANTHROPIC_API_KEY: " KEY && \
  printf 'ANTHROPIC_API_KEY=%s\n' "$KEY" >> .env && \
  unset KEY
# Aynı pattern her 5-6 sağlayıcı için
chmod 600 .env
```

**Opsiyon 2 — Founder dosyaya yazar (worker okur):**
```
# Founder lokal'de:
cat > /tmp/abs-provider-keys.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-...
...
EOF
chmod 600 /tmp/abs-provider-keys.env
# Sonra worker cat /tmp/abs-provider-keys.env >> /tmp/abs-customer-sim/.env
```

**Opsiyon 3 — ai-pc'ye drop:**
```
# Founder ai-pc:~/keys/ altına 6 dosya bırakır (chmod 600)
# Worker stdin pipe ile çeker
```

---

## Sprint 2M revize strateji (provider key yok hali)

STOP CRITERIA #1: "Provider key'ler erişilemez (auto-mode reddediyor + founder paste yok) →
FAZ D-J skip, FAZ B-C-E-H-I devam (provider dışı işler)"

**Devam edilebilen FAZ'lar (provider gerektirmez):**

| FAZ | Konu | Provider lazım mı | Durum |
|-----|------|--------------------|-------|
| A | Preflight + baseline | ❌ | ✅ DEVAM |
| B | Customer install (compose up) | ❌ | ✅ DEVAM (provider key'siz boot OK) |
| C | Setup wizard 6-step | Step 4-5 evet, 1-3-6 hayır | 🟡 STEPS 1-3 + 6 partial DEVAM |
| D | 6 provider live ping | ✅ ZORUNLU | 🔴 SKIP (founder paste sonrası) |
| E | First MCP + RAG + cascade chat | RAG hayır, chat evet | 🟡 RAG/MCP listing DEVAM, chat SKIP |
| F | 123 MCP tool kategorik | Generation tool'lar evet | 🟡 PARTIAL — system/quota/RAG OK, gen SKIP |
| G | Cascade fallback + 6-down 503 | "6 invalid" zaten provider key yokluğu = UAT-044 fırsat | 🟢 DEVAM (no-key = all-providers-down test) |
| H | Admin panel + KVKK | ❌ | ✅ DEVAM |
| I | Edge cases (license/auth/RLS/rate) | ❌ | ✅ DEVAM |
| J | Çıktı kalitesi (Türkçe 50 prompt) | ✅ ZORUNLU | 🔴 SKIP |
| K | UX scorecard | ❌ | ✅ DEVAM (scorecard'a "provider testi yapılamadı" not) |
| L | Bug log | ❌ | ✅ DEVAM |
| M | Report | ❌ | ✅ DEVAM (cert footer 🟡 RC notu) |

**Worker karar:** FAZ A-C-E-G(no-key)-H-I-K-L-M zincirle, FAZ D + F-generation + J founder paste
sonrası ayrı sprint (Sprint 2M-Provider-Live veya 2N hot-fix) açılır.

**Cert footer impact:** FAZ M'de cert Section XI 🟢 GREEN damgalanamaz — 🟡 RC (provider live
test eksik) notu eklenir.

---

## Founder aksiyon

1. Yukarıdaki 3 opsiyondan birini seç + 5-6 provider key yerleştir
2. Worker'a "provider keys hazır" sinyal ver
3. Worker FAZ D + F-generation + J'yi ayrı zincir olarak çalıştırır
4. Cert footer 🟡 → 🟢 upgrade

**Tahmini ek süre (founder paste sonrası):** 2-3 saat (sadece eksik FAZ'lar).

---

**Hazırlayan:** Sprint 2M Worker (autonomous chain)
**Lesson 13 enforce:** Bu dokümanda hiçbir API key plaintext görünmez — sadece dosya
isim envanteri ve paste pattern'i.
