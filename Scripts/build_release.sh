#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/QuotaBeaconReleaseDerivedData}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

mkdir -p "$DERIVED_DATA"
xcodebuild \
  -project "$ROOT/AIQuotaMonitor.xcodeproj" \
  -scheme AIQuotaMonitor \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  build

print "$DERIVED_DATA/Build/Products/Release/QuotaBeacon.app"
