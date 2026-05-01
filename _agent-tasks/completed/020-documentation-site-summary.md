# Task 020 — Documentation Site (MkDocs Material) — SUMMARY

**Status:** DONE
**Tarih:** 2026-04-27

## Özet

| Metrik | Önce | Sonra | Δ |
|---|---|---|---|
| pytest backend | 310 + 2 skip | **316 + 2 skip** | **+6** |
| MCP tool | 104 | **104** | 0 (yeni MCP yok, doc only) |
| Yeni dosya | — | 11 (mkdocs.yml + 6 doc + 2 script + 1 workflow + 1 test) |
| MkDocs build | — | **strict OK**, 0 warnings, site/ üretildi |

## Modüller

### A — MkDocs Config ✅
- `mkdocs.yml` (Material theme, dark/light palette blue, search + content.code.copy + navigation.tabs).
- 9 top-level nav: Ana Sayfa / Setup Guide / Architecture / API Reference / Operations (4 alt) / Design (3 alt) / FAQ / CHANGELOG / Research (6 alt) — toplam 22 entry.

### B — 6 yeni docs ✅
- `docs/index.md` (~250 kelime) — landing page.
- `docs/setup-guide.md` (~1100 kelime) — Docker Compose 8 adımda kurulum.
- `docs/troubleshooting.md` (~700 kelime) — 11 yaygın hata + çözüm.
- `docs/faq.md` (~400 kelime, 15 soru) — Ürün / Teknik / Lisans / Veri / Operasyon kategorilere göre.
- `docs/CHANGELOG.md` — 010-020 task delta'ları, tek satır + tarih.
- `docs/api-reference.md` (929 satır, 104 tool) — **otomatik üretildi**.

### C — API Reference Generator ✅
- `scripts/gen_api_reference.py` (~140 satır) — `mcp_server.list_tools()` → markdown render, kategorilere göre grup, parameters tablosu, alfabetik sıralı.
- 11 kategori: Sistem & Sağlık, Provider — Anthropic/Groq/Cerebras/Gemini/Cloudflare/Cohere/Lokal, Pipeline, RAG, Fullstack, Diğer.

### D — Build Script + GitHub Pages Workflow ✅
- `scripts/build_docs.sh` — pip install + gen_api_reference + `mkdocs build --strict`.
- `.github/workflows/docs.yml` — push to main → checkout + Python 3.13 + build + actions/upload-pages-artifact + deploy-pages.
- `.gitignore` += `site/`.

## Test Sonuçları

```
$ .venv/bin/pytest -q --tb=no
316 passed, 2 skipped in 7.50s
$ tool count → 104
```

Yeni testler (6 — `test_docs_files_exist.py`):
- index_md_exists ≥ 150 words
- setup_guide ≥ 500 words
- api_reference ≥ 500 words + auto-gen marker
- troubleshooting ≥ 400 words
- faq ≥ 300 words + ≥ 15 questions
- changelog includes Task 010/015/017/019

## Smoke Evidence

`/tmp/abs-020-smoke/evidence/` (4/4):
1. `01_mkdocs_build_log.txt` — mkdocs build --strict, 0.36s, 0 warnings.
2. `02_site_index_exists.txt` — `site/index.html` 31060 bytes.
3. `03_api_reference_md.txt` — `docs/api-reference.md` 929 satır.
4. `04_navigation_check.json` — site_name + nav_top_count=9 + total=22.

## DoD Kontrol Listesi (Spec §6)

- [x] mkdocs.yml + 6 yeni .md (index, setup-guide, api-reference, troubleshooting, faq, CHANGELOG)
- [x] gen_api_reference.py + sync (104 tool, _REGISTERED_COUNT eşleşiyor)
- [x] build_docs.sh + GH Actions workflow (docs.yml)
- [x] mkdocs build --strict warnings=0
- [x] pytest **316** + tool **104**
- [x] 4 smoke evidence valid
- [x] backend regression yeşil (310 → 316 sadece +6 doc test, mevcut testler etkilenmedi)
- [x] summary + completed/

## Planlayıcıya Notlar

1. **`docs.abs.automatiabcn.com` DNS** — kullanıcı manuel CNAME ekleyecek (örn. CNAME → `automatiabcn.github.io`); workflow GitHub Pages'e deploy ediyor ama özel domain için DNS bekliyor.
2. **MkDocs 2.0 deprecation banner** — Material 9.7.6 build ediyor ama mkdocs 2.0 plugin sistemini kıracak. 2026 sonu için Material vNext'e migrate düşünülebilir (022+).
3. **Research/ alt klasör** nav'a eklendi (6 sayfa) — ham research notları olduğundan içerik dağınık; 021/022'de temizlenebilir.
4. **GH Actions workflow live API'a dokunmuyor** — Stripe / vault key gibi secret kullanmıyor.
5. **api-reference.md regen her release'de** — manual edit YOK, otomatik script üretir.
