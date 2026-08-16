#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/QuotaBeaconReleaseDerivedData}"
APP="${APP_PATH:-$DERIVED_DATA/Build/Products/Release/QuotaBeacon.app}"
VERSION="${VERSION:-0.1.0}"
OUTPUT="$ROOT/dist"
ARCHIVE="$OUTPUT/QuotaBeacon-$VERSION-macOS.zip"
STAGING="/tmp/QuotaBeaconPackage-$$"
FOLDER="$STAGING/QuotaBeacon-$VERSION"

cleanup() { /bin/rm -rf "$STAGING"; }
trap cleanup EXIT

[[ -d "$APP" ]] || { print -u2 "Missing app: $APP (run Scripts/build_release.sh first)"; exit 1; }
mkdir -p "$OUTPUT"
mkdir -p "$FOLDER"
/usr/bin/ditto --norsrc --noextattr --noqtn "$APP" "$FOLDER/QuotaBeacon.app"
/bin/cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$ROOT/CHANGELOG.md" "$FOLDER/"
/bin/cp "$ROOT/docs/security-privacy.md" "$ROOT/docs/distribution.md" "$FOLDER/"
/usr/bin/ditto -c -k --norsrc --noextattr --noqtn --keepParent "$FOLDER" "$ARCHIVE"
/usr/bin/shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
print "$ARCHIVE"
