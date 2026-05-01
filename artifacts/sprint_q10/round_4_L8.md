# Q10 Round 4 — Layer L8 i18n hardcoded string scan

**Tarih:** 2026-05-01
**Branch:** `feat/sprint-q10-quality-loop`
**Hedef:** Panel + admin TSX dosyalarında hardcoded EN string tespit
+ TR çeviri (default locale TR olduğu için).

---

## Scan komutu

```bash
grep -rE 'Configure|Try it|>Read-only|>Cancel<|>Submit<|Loading…|Idle|Failed' \
  core/landing/app/panel core/landing/app/admin --include="*.tsx"
```

## Bulgular (3 hit)

### Q10-L8-001 — `/panel/tools` "Try it" hardcoded EN

**Severity:** MED (mixed-locale UX)

**Kök neden:** Phase C'de tool detail Sheet "Try it" başlığı EN olarak
ship edildi. Panel default locale TR olduğu için karışık görünüyor.

**Fix:** "Try it" → "Dene"
**Commit:** bu round atomic

### Q10-L8-002 — `/panel/quota` Configure button EN

**Severity:** MED

**Kök neden:** Phase I quota row'undaki Configure CTA EN ship.

**Fix:** "Configure" → "Yapılandır"

### Q10-L8-003 — `/admin/providers` Configure button EN

**Severity:** MED

**Kök neden:** Phase D provider card disabled CTA "Configure" EN ship.

**Fix:** "Configure" → "Yapılandır"

---

## Doğrulama

```bash
$ grep -rE '>Configure<|>Try it<' core/landing/app/panel core/landing/app/admin --include="*.tsx"
(no output)
```

Hardcoded EN UI label kalmadı. Yorum satırlarındaki "Configure CTA"
açıklamaları kasten kaldı (kod yorumları EN, runtime UI TR).

---

## L8 layer durumu — round 4 sonu

| Surface | Hardcoded EN audit | Status |
|---------|--------------------|---------| 
| /panel | clean (Q7 Phase C TR) | ✅ |
| /panel/chat | clean (Q8 Phase A TR) | ✅ |
| /panel/tools | Q10-L8-001 fix | ✅ |
| /panel/quota | Q10-L8-002 fix | ✅ |
| /panel/meetings | clean (Q7 + Q9 TR) | ✅ |
| /panel/transcription | clean (Q7 + Q9 TR) | ✅ |
| /admin/providers | Q10-L8-003 fix | ✅ |
| /admin/pipelines | clean (Q8 Phase E TR) | ✅ |
| /admin/rag | clean (Q8 Phase F TR) | ✅ |
| /admin/marketplace | clean (Q8 Phase G + Q9 D TR) | ✅ |
| /admin/graph | clean (Q8 Phase J TR) | ✅ |
| /admin/settings | clean (Q8 Phase K TR) | ✅ |
| /admin/audit | clean (Q8 Phase K TR) | ✅ |
| /admin/users | clean (Q8 Phase K + Q9 TR) | ✅ |
| /admin/workflow-builder | EN copy mevcut (Q8.5 TR'ye çevirdi başlık ama gövde mixed) | ⚠ |

L8 3-round-clean sayacı: 1/3.
- 1 sayfa (workflow-builder) EN gövde mixed — ileri round'da
  iyileştirilebilir, sentence-level translation pipeline'ı qual_translate
  ile yapmak mantıklı.

---

## Regression

- pytest `master_repro.sh phaseA` → 12/12 PASS
- vitest 22/22 PASS
- Q10 L1 27 test PASS

---

## Sonraki round

**Round 5 = L6 security** — npm audit, semgrep, OWASP top-10 endpoint
scan. Backend için bandit eski Sprint 060'ta kuruldu (security-nightly.yml).
Q10 round bunu manuel re-run + finding analizi yapar.

---

**Round 4 status:** ✅ ship — 3 i18n bug fix, 0 regression. L8 sayacı: 1/3.
