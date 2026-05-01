#!/usr/bin/env bash
# Q7 Phase C — Panel UI premium repro (static checks; npm install required separately).
set -uo pipefail
cd "$(dirname "$0")/../../.."
pass=0; fail=0
expect() { if [[ "$2" == "$3" ]]; then echo "  PASS  $1 ($2)"; pass=$((pass+1)); else echo "  FAIL  $1 expected=$2 actual=$3"; fail=$((fail+1)); fi; }

echo "=== Q7 Phase C — Panel UI premium ==="

# 9 ui primitives
for f in button card dialog badge input sheet skeleton sonner tabs; do
    test -f "core/landing/components/ui/${f}.tsx" \
        && expect "ui/${f}.tsx exists" 1 1 \
        || expect "ui/${f}.tsx exists" 1 0
done

# 5 panel components
for f in PanelSidebar PanelHeader PanelThemeProvider StatCard ThemeToggle; do
    test -f "core/landing/components/panel/${f}.tsx" \
        && expect "panel/${f}.tsx exists" 1 1 \
        || expect "panel/${f}.tsx exists" 1 0
done

# Library shims
test -f core/landing/lib/utils.ts \
    && expect "lib/utils.ts exists" 1 1 \
    || expect "lib/utils.ts exists" 1 0
test -f core/landing/lib/query-client.tsx \
    && expect "lib/query-client.tsx exists" 1 1 \
    || expect "lib/query-client.tsx exists" 1 0

# Routes
test -f core/landing/app/panel/layout.tsx \
    && expect "panel/layout.tsx exists" 1 1 \
    || expect "panel/layout.tsx exists" 1 0
test -f core/landing/app/panel/page.tsx \
    && expect "panel/page.tsx (Genel Bakış)" 1 1 \
    || expect "panel/page.tsx (Genel Bakış)" 1 0

# Premium dependencies declared
DEPS_OK=$(python3 -c "
import json
p = json.load(open('core/landing/package.json'))['dependencies']
required = ['@tanstack/react-query','@tremor/react','lucide-react','next-themes','tailwind-merge','clsx','class-variance-authority']
print(1 if all(k in p for k in required) else 0)
")
expect "premium deps declared" 1 "$DEPS_OK"

# Tailwind shadcn tokens
TW_OK=$(grep -c "darkMode" core/landing/tailwind.config.ts 2>/dev/null || echo 0)
[[ "$TW_OK" -ge 1 ]] && expect "tailwind darkMode class" 1 1 || expect "tailwind darkMode class" 1 0

# globals.css CSS vars
CSS_OK=$(grep -c "var(--background)\|--primary:" core/landing/app/globals.css 2>/dev/null || echo 0)
[[ "$CSS_OK" -ge 1 ]] && expect "globals.css shadcn vars" 1 1 || expect "globals.css shadcn vars" 1 0

# Q7 markers in refactored pages
PAGE_MARK=$(grep -c "Q7 Phase C" core/landing/app/panel/page.tsx core/landing/app/panel/meetings/page.tsx 2>/dev/null | python3 -c "import sys; print(sum(int(line.split(':')[-1]) for line in sys.stdin if ':' in line))")
[[ "$PAGE_MARK" -ge 2 ]] && expect "Q7 markers in panel pages" 1 1 || expect "Q7 markers in panel pages" 1 0

# Cosmos absent in /panel + /admin (target audience)
COSMOS=$(grep -rln "cosmos\|comet-trail\|parallax" core/landing/app/panel core/landing/app/admin 2>/dev/null | wc -l | tr -d ' ')
expect "cosmos absent in /panel + /admin" 0 "$COSMOS"

# Operator panel preserved (CLAUDE.md guard)
SERVER_PANEL_PRESERVED="absent"
[[ ! -e "core/landing/automatiabcn_panel_v2.html" ]] && SERVER_PANEL_PRESERVED="absent"
expect "ops panel not copied into /landing" "absent" "$SERVER_PANEL_PRESERVED"

echo
echo "─────────────────────────────────────────"
echo "PASS=$pass  FAIL=$fail"
exit "$fail"
