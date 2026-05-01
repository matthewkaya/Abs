# Task 020 — Documentation Site (MkDocs Material Build)

**Status:** READY (Worker)
**Tahmini süre:** 2-3 saat
**Bağımlı task'lar:** 014 (provider configs YAML), 017 (billing-runbook + first-customer-playbook), tüm önceki tasklar (architecture/design-decisions docs)
**Hedef sonuç:** `docs/` mevcut markdown dosyalarını MkDocs Material ile arama yapılabilir, navigasyonlu, brand-aligned static site'a derle. Self-host müşteri için tam dokümantasyon.

---

## 0. Bağlam

`docs/` altında zaten yazılmış 8+ markdown var:
- `README.md`, `architecture.md`, `design-decisions.md`, `open-questions.md`, `operations.md`
- `vision.md`, `billing-runbook.md` (017), `first-customer-playbook.md` (017)
- `research/` alt klasör

Müşteri için yazılmamış kritik docs:
- Setup guide (kurulum 15 dk)
- API reference (102+ MCP tool listesi)
- Troubleshooting (yaygın hatalar)
- FAQ
- CHANGELOG

020: Yeni docs ekle + MkDocs Material build + GitHub Pages deploy hazır + brand color/logo.

---

## 1. Amaç (DoD)

- [ ] `mkdocs.yml` config (Material theme, navigation, search, brand)
- [ ] 6 yeni markdown:
  - `docs/setup-guide.md` (~1200 kelime, 15dk install)
  - `docs/api-reference.md` (~1500 kelime, MCP tool listesi otomatik gen)
  - `docs/troubleshooting.md` (~800 kelime)
  - `docs/faq.md` (~600 kelime, 15 soru)
  - `docs/CHANGELOG.md` (010-019 milestone'lar)
  - `docs/index.md` (landing page için docs)
- [ ] MCP tool listesi otomatik üretilsin (`scripts/gen_api_reference.py`)
- [ ] Build script `scripts/build_docs.sh` — `mkdocs build`
- [ ] GitHub Pages workflow `.github/workflows/docs.yml`
- [ ] Build çıktısı `site/` klasörü (gitignored)
- [ ] 6 yeni test (markdown render, navigation, MCP listesi senkron)
- [ ] 1 smoke evidence (build log + site/index.html exist)
- [ ] backend hâlâ 310 test yeşil

---

## 2. Modüller

### Modul A — MkDocs Config
`mkdocs.yml` (`docs/` parent'ında):
```yaml
site_name: Automatia ABS Documentation
site_url: https://docs.abs.automatiabcn.com/
site_description: Self-host AI orchestration for Claude Code
repo_url: https://github.com/automatiabcn/abs
theme:
  name: material
  palette:
    - media: "(prefers-color-scheme: light)"
      scheme: default
      primary: blue
      accent: blue
    - media: "(prefers-color-scheme: dark)"
      scheme: slate
      primary: blue
      accent: blue
  features:
    - navigation.tabs
    - navigation.sections
    - search.suggest
    - search.highlight
    - content.code.copy
nav:
  - Home: index.md
  - Setup Guide: setup-guide.md
  - Architecture: architecture.md
  - API Reference: api-reference.md
  - Operations:
      - Billing Runbook: billing-runbook.md
      - First Customer Playbook: first-customer-playbook.md
      - Troubleshooting: troubleshooting.md
  - Design:
      - Decisions: design-decisions.md
      - Vision: vision.md
      - Open Questions: open-questions.md
  - FAQ: faq.md
  - CHANGELOG: CHANGELOG.md
markdown_extensions:
  - admonition
  - pymdownx.details
  - pymdownx.superfences
  - pymdownx.highlight
  - pymdownx.inlinehilite
  - pymdownx.snippets
  - tables
  - toc:
      permalink: true
plugins:
  - search
```

### Modul B — Yeni Docs (qwen32b ile metin)
- `setup-guide.md` (~1200 kelime): Docker Compose 15dk install, Linux server, sops/age vault setup, ilk panel açılış, lisans aktive
- `troubleshooting.md` (~800 kelime): yaygın 15 hata + çözüm (vault decrypt fail, Stripe webhook 400, demo expired, MCP tool not found, vb.)
- `faq.md` (~600 kelime, 15 soru): "ABS nedir?", "Anthropic TOS uygun mu?", "Veri gizliliği?", "Self-host vs cloud?", vb.
- `CHANGELOG.md`: 010-019 milestone'lar (her task tek satır + tarih)
- `index.md`: docs landing — 4 ana bölüm link (Setup, API, Operations, FAQ) + brand hero

### Modul C — API Reference Generator
`scripts/gen_api_reference.py` (yeni, ~120 satır):
```python
"""MCP tool listesini Python introspection ile otomatik üret.

Output: docs/api-reference.md
- Her tool için: ad, açıklama (docstring 1. satır), parametreler (signature)
- Kategorilere göre grup (license, billing, rag, mcp, vb.)
"""
import inspect
from app.mcp.server import mcp_server, _REGISTERED_COUNT
import asyncio

async def main():
    tools = await mcp_server.list_tools()
    # her tool için: tool.name, tool.description, tool.inputSchema
    # markdown render
    ...
```

Cron-friendly — release pipeline'ında otomatik koşar.

### Modul D — Build Script + GitHub Actions
`scripts/build_docs.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
pip install mkdocs mkdocs-material
python scripts/gen_api_reference.py
mkdocs build --strict
echo "Built site/ — entry: site/index.html"
```

`.github/workflows/docs.yml`:
```yaml
name: docs
on: { push: { branches: [main], paths: [docs/**, mkdocs.yml] } }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.13" }
      - run: bash scripts/build_docs.sh
      - uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./site
```

---

## 3. Test Stratejisi (6 test)

| Dosya | Test |
|---|:-:|
| `tests/test_docs_files_exist.py` | 6 (her yeni .md dosya var, min word count) |
| `tests/test_mkdocs_config_valid.py` | 1 (`mkdocs build --strict` exit 0) |
| `tests/test_api_reference_sync.py` | 1 (script üretimi tool count == _REGISTERED_COUNT) |
| `tests/test_build_script_exists.py` | 1 (build_docs.sh + workflow var) |

Toplam test: 310 → 316.

---

## 4. Smoke Evidence (`/tmp/abs-020-smoke/evidence/`)

1. `01_mkdocs_build_log.txt` — `mkdocs build --strict` stdout (no warnings)
2. `02_site_index_exists.txt` — `ls -la site/index.html` çıktısı
3. `03_api_reference_md.txt` — `wc -l docs/api-reference.md` ≥ 200 satır
4. `04_navigation_check.json` — `mkdocs.yml` parsed nav sections count

---

## 5. Adım Adım

```
1. baseline pytest 310 + tool 104
2. pip install mkdocs mkdocs-material (.venv'e)
3. Modul A: mkdocs.yml + docs/index.md
4. Modul B: 5 yeni markdown (qwen32b ile yazdır, kontrol et)
5. Modul C: gen_api_reference.py + ilk run
6. Modul D: build_docs.sh + GitHub workflow
7. mkdocs build --strict (warnings 0)
8. Modul testleri yaz (6 test)
9. Smoke 4 evidence
10. summary + completed/
```

## 6. DoD Checklist

```
[ ] mkdocs.yml + 6 yeni .md
[ ] gen_api_reference.py + sync test
[ ] build_docs.sh + GH Actions workflow
[ ] mkdocs build --strict warnings=0
[ ] pytest 316 + tool 104 (yeni MCP tool yok)
[ ] 4 smoke evidence
[ ] backend regression yeşil
[ ] summary + completed/
```

## 7. Worker Notları

1. `mkdocs` sadece `.venv` içine kur, sistem Python'a bulaşma.
2. Site `site/` klasörü `.gitignore`'a ekle.
3. Markdown delegation: `ask "..." qwen32b` (her docs için). Çıktıyı kontrol et — code block syntax doğru, link'ler relative.
4. `api-reference.md` her release'de regen — manuel düzenleme YOK (otomatik tool listesi).
5. CHANGELOG: 010-019 her task için 1 satır (tarih + başlık + delta).
6. FAQ: open-questions.md ve design-decisions.md'den içerik damıt; ham soru-cevap formatı.
7. GitHub Pages domain `docs.abs.automatiabcn.com` — DNS kullanıcı manuel set edecek (workflow runs ama DNS yok ise 404).
