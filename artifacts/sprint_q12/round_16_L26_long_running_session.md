# Q12 — Round 16 — L26 long-running session JWT lifecycle

**Tarih:** 2026-05-03
**Layer:** L26 — long-running session (Q12 Session 2 yeni)
**Branch:** `feat/sprint-q12-deep-quality`
**Worker:** Opus 4.7 (1M ctx)

---

## 0. Hedef

Brief original talebi: 24h idle browser tab, JWT auto-refresh,
WebSocket reconnect, memory leak heap snapshots (Playwright +
Chromium DevTools Protocol).

**Frontend dev server bu CI ortamında ayakta değil**. Browser-level
surface deferred. Yine de L26 promise'ini taşıyan **backend
invariant'lar** test edildi:

1. Geçmişte expire olmuş JWT cookie → temiz 401 + audit reason="expired"
2. Tampered JWT (signature flip) → temiz 401 + audit reason="invalid"
3. Garbled cookie → temiz 401 + audit reason="invalid"
4. Eksik cookie path `auth.session.decode` event çıkarmaz (sadece
   `auth.me.check` — Round 13 contract korunur)
5. OAuth refresh token reuse-after-rotation → invalid_grant

---

## 1. Bulgu — Q12-L26-001 (LOW observability fragility, fix shipped)

**Lokasyon (Round 13 sonrası):** `core/backend/app/api/auth.py:current_admin`

```python
# Round 13 (pre-Round 16):
except HTTPException as http_exc:
    emit_event(
        request,
        action="auth.session.decode",
        outcome="denied",
        reason="expired" if http_exc.status_code == 401 \
                            and "süresi" in str(http_exc.detail) else "invalid",
        ...
    )
```

`reason` field Türkçe i18n string'inden çıkarsanıyor: `"süresi" in detail`.
Eğer ileride detail mesajı translate edilir veya jinja-template'lenirse
(örn. `t("errors.session_expired", lang)` patterner i18n dönüşümünden
geçen bir string), `"süresi"` substring kaybolur ve reason silently
`"invalid"` olarak yazılır. Ops dashboard'da expired credential reuse
incident'ları "tampered" gibi görünür → triage yanlışı.

**Fix (shipped):** typed exception sentinel'ı.

```python
class _SessionExpired(HTTPException):
    def __init__(self) -> None:
        super().__init__(status_code=401, detail="Oturum süresi doldu")

class _SessionInvalid(HTTPException):
    def __init__(self) -> None:
        super().__init__(status_code=401, detail="Session invalid")

def _decode_token(token: str) -> Dict:
    try:
        return jwt.decode(...)
    except ExpiredSignatureError as exc:
        raise _SessionExpired() from exc
    except JWTError as exc:
        raise _SessionInvalid() from exc

# current_admin AND /me:
try:
    return _decode_token(token)
except _SessionExpired:
    emit_event(..., reason="expired", ...)
    raise
except _SessionInvalid:
    emit_event(..., reason="invalid", ...)
    raise
```

`/me` endpoint Round 13'te `_decode_token` çağırıyordu ama emit_event
yoktu — fix bu boşluğu da kapatıyor.

---

## 2. Tests — `core/backend/tests/test_q12_l26_long_running_session.py` (9 test)

```
TestQ12L26ExpiredSessionAuditReason (5 parametrize):
  expired_seconds_ago = [1, 3600, 86400, 7*86400, 30*86400]
  → her biri 401 + audit.reason == "expired"
  Past-exp aralık: 1 saniye, 1 saat, 24 saat, 7 gün, 30 gün
  (clock skew, idle tab, sleep-mode laptop, archived backup
   replay senaryolarını kapsar)

TestQ12L26TamperedSessionAuditReason:
  test_tampered_cookie_returns_401_with_invalid_reason
    → mint valid JWT → flip signature byte → 401 + "invalid"
  test_garbled_cookie_returns_401_with_invalid_reason
    → "definitely.not.a.jwt" → 401 + "invalid"

TestQ12L26AuditEmissionHygiene:
  test_missing_cookie_emits_check_not_decode
    → eksik cookie auth.me.check çıkarmalı, auth.session.decode
      olmamalı (Round 13 contract pin)

TestQ12L26OAuthRefreshSingleUse:
  test_refresh_token_second_use_rejected
    → exchange_code → refresh (rotates) → ORIGINAL refresh tekrar
      → OAuthError("invalid_grant"). Stolen-token replay guard.
```

**Sonuç:** 9/9 PASS.

---

## 3. Layer state

| Layer | Counter | Notes |
|-------|---------|-------|
| **L17** | **3/3 ⭐** | bundle break-even validator + unit + CI gate |
| **L18** | **3/3 ⭐** | cold-cache + CDP throttle 12/12 PASS |
| **L19** | **3/3 ⭐** | backwards compat 11/11 + 1473 full suite PASS |
| **L20** | **3/3 ⭐** | chaos 5/5 PASS (redirect-loop fix) |
| **L21** | **1/3** | fresh-deploy drill (safe variant 3/3 PASS) |
| **L22** | **1/3** | race condition fix (setup wizard TOCTOU 4/4 PASS) |
| **L23** | **1/3** | observability fix (req_id + emit_event 9/9 PASS) |
| **L24** | **1/3** | secret leakage fix (magic_token + Stripe 5/5 PASS) |
| **L25** | **0/3** | pending Round 17 |
| **L26** | **1/3** | JWT lifecycle hardening (typed exceptions + 9/9 PASS) |

**5/5 Q12 Session 2 yeni layer'ın 4'ü 1/3'e ulaştı.**

---

## 4. Atomic commit

```
fix(q12/L26): Round 16 JWT lifecycle — typed _SessionExpired/_SessionInvalid + /me audit + 9 tests PASS
```
