#!/bin/zsh
set -euo pipefail

APP="${1:?usage: Scripts/verify_release.sh /path/to/QuotaBeacon.app}"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --verbose=4 "$APP" 2>&1 | /usr/bin/grep -E 'Identifier=|TeamIdentifier=|Runtime Version|Signature='
spctl --assess --type execute --verbose=2 "$APP"
print "Release verification passed."
