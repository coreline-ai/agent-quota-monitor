#!/bin/zsh
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

forbidden_pattern='TokenRemain|UsageDock|PixelRobot|CodexBar|ClaudeBar'
scan_paths=(
  "$root/AIQuotaMonitor"
  "$root/AIQuotaMonitorTests"
  "$root/AIQuotaMonitorUITests"
  "$root/Config"
)

if rg --hidden --glob '!*.md' --glob '!*.strings' "$forbidden_pattern" "${scan_paths[@]}"; then
  echo "Greenfield audit failed: reference-project identifiers were found." >&2
  exit 1
fi

echo "Greenfield audit passed."

