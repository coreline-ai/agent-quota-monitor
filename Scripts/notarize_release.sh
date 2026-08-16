#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:-0.1.0}"
ARCHIVE="${ARCHIVE_PATH:-$ROOT/dist/QuotaBeacon-$VERSION-macOS.zip}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing xcrun notarytool Keychain profile}"
[[ -f "$ARCHIVE" ]] || { print -u2 "Missing archive: $ARCHIVE"; exit 1; }

xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
print "ZIP notarization accepted. A ZIP itself cannot be stapled; verify after extraction."
