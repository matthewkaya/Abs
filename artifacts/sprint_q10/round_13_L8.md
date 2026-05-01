# Q10 Round 13 — Layer L8 i18n re-scan

**Tarih:** 2026-05-01
**Branch:** `feat/sprint-q10-quality-loop`
**Hedef:** Q9 sonrası (filter bar, dialog modal, vb.) yeni hardcoded
EN string var mı? Panel TR locale default olduğu için karışık-locale
UX bug avı.

---

## Scan komutu

```bash
grep -rEn '>[A-Z][a-z]+( [A-Za-z]+)*<' \
  core/landing/app/panel core/landing/app/admin --include="*.tsx"
grep -rEn 'title="[A-Z][a-z]+( [A-Z][a-z]+)*"' \
  core/landing/app/panel core/landing/app/admin --include="*.tsx"
grep -rEn 'placeholder="[A-Z][a-z]' \
  core/landing/app/panel core/landing/app/admin --include="*.tsx"
```

## Bulgular (5 hit, 2 sayfa)

### Q10-L8-004 — `/admin/providers` Test Now button + 3 inline reference

**Severity:** MED (mixed-locale, primary CTA)

**Hits:**
- L229 `<Button>{test.isPending ? "Çağrı yapılıyor…" : "Test Now"}` — button label
- L238 `Sol → sağ deneme sırası. Test Now çağrısı sırasında seçilen…` — CardDescription inline
- L367 `Test Now butonu çağrıları + ileride canlı SSE feed.` — recent-calls
- L373 `<kbd>Test Now</kbd> ile başla.` — empty-state hint

**Fix:** "Test Now" → "Şimdi Test Et" (4 yerde tutarlı)
**Translation source:** kimi K2.5 (CF) — 17s, "Şimdi Test Et" professional UI label.

### Q10-L8-005 — `/admin/providers` "Cascade rank" badge

**Severity:** LOW

**Kök neden:** Provider card'daki cascade sıra numarası label'ı EN ship.

**Fix:** "Cascade rank" → "Cascade sırası" (cascade product term lowercase, sıra TR).

### Q10-L8-006 — `/panel` "Claude Quota" StatCard title

**Severity:** MED (panel ana sayfa, görünür alan)

**Kök neden:** Phase B Claude quota stat card EN ship; aynı sayfada
diğer stat card'lar TR ("Cascade", "Sağlayıcılar", "Maliyet").

**Fix:** `title="Claude Quota"` → `title="Claude Kotası"`

---

## Doğrulama

```bash
$ grep -rEn 'Test Now|Cascade rank|Claude Quota' \
    core/landing/app/admin core/landing/app/panel --include="*.tsx"
(no output)
```

Re-scan EN-label hits:
```bash
$ grep -rEn '>[A-Z][a-z]+( [A-Za-z]+)*<' \
    core/landing/app/panel core/landing/app/admin --include="*.tsx" | grep -v className
core/landing/app/panel/tools/page.tsx:208     <span>Dene</span>
core/landing/app/panel/transcription/page.tsx:417    <strong>Durdur</strong>
core/landing/app/panel/meetings/page.tsx:262         <option>Beklemede</option>
core/landing/app/panel/meetings/page.tsx:264         <option>Hata</option>
core/landing/app/admin/settings/page.tsx           <Button>Kaydet</Button> (×4)
core/landing/app/admin/settings/page.tsx:100       <Badge>Solo</Badge>
core/landing/app/admin/providers/page.tsx:340      <span>Mod</span>
core/landing/app/admin/users/page.tsx              <option>Admin</option>, <option>Okur</option>
```

Tüm kalan hit'ler TR (Dene, Durdur, Beklemede, Hata, Kaydet, Solo,
Mod, Admin, Okur). EN hit = 0.

Product noun fixt'leri (Notion Sync, Linear Sync, Zendesk Tickets,
Anthropic Mock) **kasten EN** — proper noun / brand name.

---

## TS check

```bash
$ npx tsc --noEmit -p . 2>&1 | grep -E 'providers|panel/page'
(no output — clean)
```

Pre-existing deprecation warnings (WorkflowChatPanel, MarketplacePanel,
WorkflowCanvasFlow) Round 13 scope dışı.

---

## L8 layer durumu — round 13 sonu

| Surface | Hardcoded EN | Status |
|---------|--------------|--------|
| /panel | Q10-L8-006 fix | ✅ |
| /panel/chat | clean | ✅ |
| /panel/tools | clean (Round 4) | ✅ |
| /panel/quota | clean (Round 4) | ✅ |
| /panel/meetings | clean | ✅ |
| /panel/transcription | clean | ✅ |
| /admin/providers | Q10-L8-004,005 fix | ✅ |
| /admin/pipelines | clean | ✅ |
| /admin/rag | clean | ✅ |
| /admin/marketplace | clean | ✅ |
| /admin/graph | clean | ✅ |
| /admin/settings | clean | ✅ |
| /admin/audit | clean | ✅ |
| /admin/users | clean | ✅ |
| /admin/workflow-builder | EN gövde mixed (Round 4 not) | ⚠ deferred |

L8 3-round-clean sayacı: **1/3 → 2/3**.

---

## Regression

- TS check (modified files): clean
- Round 4 fix'leri (Try it/Configure×2): regression yok, hâlâ TR.

---

## Atomic commit

`d6f2583` — fix(q10/L8): Round 13 — Q10-L8-004..006 hardcoded EN → TR fix

---

**Round 13 status:** ✅ ship — 5 EN string fix in 2 page, 0 regression.
L8 sayacı 1/3 → 2/3. Bir round daha temiz = L8 FULL CLEAN (3/3).
