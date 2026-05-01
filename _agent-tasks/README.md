# Agent Tasks — Prompt Delegation

Bu klasör, **ikinci terminal'de çalışan Claude** için hazır prompt'ları içerir. Iş akışı:

1. **Planlayıcı Claude** (bu sohbet): strateji, karar, prompt üretir
2. **İşçi Claude** (terminal 2, `abs-server-product` klasöründe açılır): prompt'u uygular
3. **Enes** (koordinatör): prompt'u bir terminalden diğerine kopyalar, sonuç raporunu geri getirir

## Kurallar (İşçi Claude için)

Her task dosyası `001-xxx.md`, `002-yyy.md` gibi sıralıdır. İşçi Claude:

1. Task dosyasını oku
2. **Bağlam + Kısıtlar** bölümüne sadık kal
3. **Beklenen Çıktı** listesindeki her maddeyi tamamla
4. Çıktıyı `completed/` altına taşı (dosya taşıma + commit note)
5. Bir sonraki task'a geçmeden **sonuç raporu** üret

## Zorunlu Kurallar (her task için geçerli)

- ❌ **SERVER klasörüne dokunma** (`/Automatia BCN/SERVER/` yolu yasak)
- ❌ Yeni task oluşturma (sadece planlayıcı Claude yapar)
- ❌ Scope dışında feature ekleme
- ❌ **SERVER widget/feature/tool ÇIKARMA YASAK** (bkz. Feature Parity Kuralı aşağıda)
- ✅ Her kod değişikliği sonrası test ekle (pytest veya jest)
- ✅ Tüm testler yeşil olmadan complete etme
- ✅ Değişiklik sonrası kısa `summary.md` yaz — ne yapıldı, ne atlandı, neden

## 🚨 Feature Parity Kuralı (KESİN YASAK — 004 düzeltmesi)

Ürün, SERVER'daki her feature'ı **korumak zorunda**. Karar referans: `docs/design-decisions.md` § 5 ("Tam Set + Fazlası").

### Yasak
- SERVER widget'ını "gereksiz" diyerek kaldırma
- SERVER MCP tool'unu "şimdi lazım değil" diyerek atlamak
- SERVER hook modülünü basitleştirmek/çıkarmak
- Panel bölümünü "MVP için önemsiz" diyerek silmek

### İzin (belirli koşullarda)
- SERVER-özel içerikler (Enes'in kişisel path'leri, 3-cihaz referansları, private URL'ler) **sil** — bu adaptasyon, feature değil
- Feature'ı **tenant-aware yap** (kullanıcı başına etki)
- Davranışı **koru**, görünümü **branding ile adapte et**

### Widget'ı kaldırmak _gerçekten_ gerekiyorsa
1. Task dosyasında **explicit olarak** "bu widget kaldırılacak" yazılı olmalı
2. Yoksa: **summary.md'ye karar + gerekçe + kullanıcıya onay gerektir** uyarısı
3. Kullanıcı onay vermeden `completed/` klasörüne geçme — **blocked/** altına al

### 004 Örneği (Yanlış Pattern)
Task 004'te 7 widget kaldırıldı (symbol explorer, quota radar, anchor nav, notif bell, theme toggle, disagree panel, vital signs). Task dosyasında explicit "kaldırılacak" yoktu. Bu yanlış. Sonuç: **004b task** açıldı, widget'lar geri getirildi.

**Dersler:**
- Task dosyası explicit değilse, **feature parity default**: koru
- Emin değilsen: önce sor (summary'de "bu widget gerekli mi?" notu), sonra sil
- Widget değerini sen belirleme — kullanıcı karar verir

## Delegation Kuralları (ZORUNLU — sistem MCP tool'larını kullan)

Bu projede **sadece kendi başına yazma**. ABS MCP tool'ları zaten kurulu, bedava ve kaliteli. Kullan:

### Ne zaman delege et

| Durum | Komut | Neden |
|---|---|---|
| 100+ satır kod yazacaksan (endpoint, service, class) | `mcp__abs__qual_code` veya `ask_kimi` | 4-model zinciri: üret → doğrula → düzelt |
| Türkçe doküman / README / açıklama | `mcp__abs__ask_qwen32b` | TR metin için en iyi |
| SERVER'dan benzer örnek lazım | `mcp__abs__rag_query` | 10K sembol indexli |
| Library docs / API araştırma | `mcp__abs__gemini_search` | Güncel web |
| Full-stack component (React form + API + DB) | `mcp__abs__fullstack` | Katman-özel model + verify |
| Test yazmak | `mcp__abs__write_tests` | CodeLlama unit test + edge |
| Yazdığın patch'i skorla | `mcp__abs__judge_patch` | AST + LLM 0-10 skor |
| Kod review | `mcp__abs__code_review` (tier=quick|standard|exhaustive) | Multi-model review |
| Karşılaştırma / tradeoff / analiz | `mcp__abs__qual_analysis` | 3 perspektif → sentez |

### Ne zaman delege **etme**

- Küçük config dosyası (< 30 satır)
- Standart template (Dockerfile, docker-compose basit, .gitignore)
- Mekanik dosya işlemi (mkdir, cp, mv)
- Git operasyonu
- Test koşma, doğrulama

### Hedef Delegation Oranı

- **Uzun kod/dokümantasyon task'ları:** %20-40 (qual-code, qual-tr kullanım)
- **Karışık task'lar:** %10-15 (dengeli)
- **Scaffold/config task'ları:** %0-5 (001 gibi)
- **Kritik path kod (hook, security, auth):** %5-15 — **delegation AZALT** (regresyon riski yüksek)

### Kritik Path Kuralı (007 dersi)

Hook, security, auth, dispatcher gibi **bir hata sistemi bloklayan** kodlarda:
- LLM-üretilen kod regresyon riski yüksek (subtle behavior değişikliği)
- Pattern okuma + manuel adaptasyon **daha güvenli**
- Test guard zorunlu (her davranış için pytest)
- Delegation oranı düşük olur — bu **doğru senior judgment**, "delegation hedefini karşılamadın" eleştirisi yok

Test 100% yeşil + davranış parity ispat edilirse, delegation oranı düşük kalabilir.

### Pragmatik Örnek (her task için)

Task 004 "panel port" diyelim. Doğru yaklaşım:
1. `Read /Users/eneseserkan/Main/Automatia BCN/SERVER/automatiabcn_panel_v2.html` (7550 satır)
2. `mcp__abs__qual_code` — "Bu HTML'i multi-tenant auth katmanı ile yeniden yaz, hardcoded path'leri env-var'a çevir, ..."
3. Output doğrula (judge_patch ile skorla)
4. `Write core/panel/index.html`
5. `pytest` test eklentisi

## Sonuç Raporu (summary.md) Zorunlu Bölümler

```markdown
# Task NNN Summary

## Ne Yapıldı
- Dosya 1 (satır, adaptasyon)
- ...

## Delegation Kullanımı
- MCP tool'lar: (hangileri, kaç kez)
- Bash/Write oranı: X/Y
- Toplam delegation: %Z (hedef karşılaştırma)

## Atlanan / Blocker
- ...

## Test Sonuçları
- pytest: X passed, Y failed
- docker build: OK/FAIL
- curl health: OK/FAIL

## Notlar Planlayıcıya
- Gelecek task'lara etki
- Karar bekleyen konular
```

## Klasör Yapısı

```
_agent-tasks/
├── README.md             # bu dosya
├── 001-scaffold.md       # docker-compose + klasör + caddyfile
├── 002-licensing.md      # Stripe webhook + JWT generator
├── 003-landing.md        # Next.js landing
├── 004-panel-port.md     # SERVER panel HTML port (auth proxy)
├── 005-orchestrator.md   # Python backend (75 MCP + 5 hook + 13 pipeline)
├── ... (sıra ile eklenir)
└── completed/
    ├── 001-scaffold-summary.md
    └── ...
```

## Task Dosyası Formatı

Her task file şu formatta:

```markdown
# Task NNN — Başlık

## Bağlam
- Proje durumu
- Bağlı task'lar (önceki task'lardan ne geliyor)

## Giriş (Mevcut Durum)
- Hangi dosyalar var
- Hangi servisler çalışıyor

## Beklenen Çıktı
- [ ] Dosya 1 (açıklama)
- [ ] Dosya 2 (açıklama)
- [ ] Test pytest 100/100

## Kısıtlar
- Python 3.11+ (veya ne gerekiyorsa)
- Belirli library sürümleri
- SERVER dokunulmaz

## Adımlar (İşçi Claude için)
1. Adım 1
2. Adım 2
3. Adım 3

## Doğrulama
- Komut: `...`
- Beklenen çıktı: `...`

## Tamamlama
Bitirince:
- `summary.md` yaz
- Bu dosyayı `completed/` altına taşı
```

## Koordinatör (Enes) İçin Akış

1. Planlayıcı Claude yeni task dosyası üretir (örn. `001-scaffold.md`)
2. Enes terminal 2'de `abs-server-product/` açar
3. Claude başlatır (veya mevcut oturumda)
4. Dosya içeriğini kopyalar, prompt olarak verir
5. İşçi Claude uygular
6. Sonuç raporu gelir
7. Enes terminal 1'de planlayıcıya "task X tamam, sonraki?" der
8. Planlayıcı `002-yyy.md` üretir → döngü devam

## Hata Durumunda

İşçi Claude bir task'ı tamamlayamazsa:
1. `summary.md`'ye NE başarısız olduğunu yaz
2. Blocker'ı net belirt (teknik sorun, karar gerekli, library eksik vb.)
3. Task'ı `completed/` yerine `blocked/` altına al
4. Planlayıcı Claude'a geri dön, çözüm üretsin

---

İlk task: `001-scaffold.md` — ABS Docker Compose + klasör + Caddy setup.
