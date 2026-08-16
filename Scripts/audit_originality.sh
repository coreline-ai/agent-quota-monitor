#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SCAN_PATHS=("$ROOT/AIQuotaMonitor" "$ROOT/AIQuotaMonitorTests" "$ROOT/AIQuotaMonitorUITests" "$ROOT/Config")
BANNED=('TokenRemain' 'UsageDock' 'CodexBar' 'ClaudeBar' 'ccusage')

failures=0
for term in "${BANNED[@]}"; do
  if /usr/bin/grep -RIn --exclude='audit_originality.sh' -- "$term" "${SCAN_PATHS[@]}"; then
    print -u2 "originality audit: prohibited reference found: $term"
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  exit 1
fi
print "Originality audit passed: no reference-project identifiers in product or test sources."
