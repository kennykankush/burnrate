#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP=".build/$CONFIG/burnrate.app"
BIN=".build/$CONFIG/burnrate"
BUNDLE=".build/$CONFIG/burnrate_Burnrate.bundle"

pkill -x burnrate 2>/dev/null || true

swift build ${CONFIG:+-c "$CONFIG"}

# Create the .app skeleton if missing. Canonical Info.plist lives at
# Resources/Info.plist; we always copy it forward so any version-bump
# done via PlistBuddy on the .app's plist also gets reflected upstream
# whenever we rebuild from a clean state.
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ -f "Resources/Info.plist" ]]; then
  cp "Resources/Info.plist" "$APP/Contents/Info.plist"
fi
if [[ ! -f "$APP/Contents/Info.plist" ]]; then
  echo "error: $APP/Contents/Info.plist missing and Resources/Info.plist not found" >&2
  exit 1
fi

cp "$BIN" "$APP/Contents/MacOS/burnrate"
# Put the SwiftPM-produced resource bundle in Contents/Resources so codesign
# accepts the bundle layout. (The legacy location at the .app root caused
# "unsealed contents present in the bundle root" errors and forced ad-hoc
# fallback even when an Apple Development identity was available.)
mkdir -p "$APP/Contents/Resources"
rm -rf "$APP/burnrate_Burnrate.bundle"
rm -rf "$APP/Contents/Resources/burnrate_Burnrate.bundle"
cp -R "$BUNDLE" "$APP/Contents/Resources/burnrate_Burnrate.bundle"

# Bundle the .icns app icon (referenced via CFBundleIconFile=AppIcon in Info.plist).
# Run scripts/build-app-icon.sh once whenever the source brand image changes.
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Codesign with a stable identity so macOS Keychain "Always Allow" persists
# across rebuilds. Without this, every rebuild produces a different signature
# and you get re-prompted for the OAuth credential on every refresh.
#
# Picks the first available codesigning identity in this order:
#   1. BURNRATE_SIGN_IDENTITY env var (override)
#   2. Apple Development cert from Xcode/Apple ID
#   3. Developer ID Application cert (paid Apple Developer accounts)
#   4. Any other valid codesigning identity
#   5. Falls back to ad-hoc signing (will keep prompting — see scripts/setup-codesigning.sh)
SIGN_IDENTITY="${BURNRATE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY=$(
    security find-identity -v -p codesigning 2>/dev/null |
    awk -F'"' '/Apple Development:/ { print $2; exit }'
  )
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY=$(
    security find-identity -v -p codesigning 2>/dev/null |
    awk -F'"' '/Developer ID Application:/ { print $2; exit }'
  )
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY=$(
    security find-identity -v -p codesigning 2>/dev/null |
    awk -F'"' '/^[[:space:]]*[0-9]+\) [A-F0-9]+ "/ { print $2; exit }'
  )
fi

ENTITLEMENT=".build/$CONFIG/burnrate-entitlement.plist"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "signing with: $SIGN_IDENTITY"
  if [[ -f "$ENTITLEMENT" ]]; then
    codesign --force --deep --options runtime \
      --sign "$SIGN_IDENTITY" \
      --entitlements "$ENTITLEMENT" \
      "$APP" 2>&1 | grep -v "replacing existing signature" || true
  else
    codesign --force --deep --options runtime \
      --sign "$SIGN_IDENTITY" \
      "$APP" 2>&1 | grep -v "replacing existing signature" || true
  fi
else
  echo "no codesigning identity found — falling back to ad-hoc (you'll keep being prompted for keychain access)"
  codesign --force --deep --sign - "$APP" 2>&1 | grep -v "replacing existing signature" || true
fi

open "$APP"
echo "launched $APP"
