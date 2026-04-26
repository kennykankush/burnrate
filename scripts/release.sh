#!/usr/bin/env bash
# Build a release-config burnrate.app, codesign it, zip it, and print the
# SHA256 you'll paste into Casks/burnrate.rb.
#
# Usage:
#   scripts/release.sh                  # uses CFBundleShortVersionString from Info.plist
#   scripts/release.sh 0.2.0            # also bumps the Info.plist version first
#
# Output:
#   .build/release/burnrate.app                          ← signed bundle
#   dist/burnrate-<version>.zip                          ← upload this to GitHub Releases
#   dist/burnrate-<version>.sha256                       ← paste into Casks/burnrate.rb

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
APP=".build/$CONFIG/burnrate.app"
BIN=".build/$CONFIG/burnrate"
BUNDLE=".build/$CONFIG/burnrate_Burnrate.bundle"
DIST="dist"
INFO_PLIST="$APP/Contents/Info.plist"
SKELETON_INFO=".build/debug/burnrate.app/Contents/Info.plist"

# 1. Optional version bump.
VERSION="${1:-}"
if [[ -n "$VERSION" ]]; then
  echo ":: bumping CFBundleShortVersionString → $VERSION"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$SKELETON_INFO"
fi

# 2. Build release config.
echo ":: swift build -c release"
pkill -x burnrate 2>/dev/null || true
swift build -c "$CONFIG"

# 3. Build the .app skeleton fresh from the debug-config skeleton.
#    (SwiftPM doesn't produce a .app on its own; we copy the structure.)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/debug/burnrate.app/Contents/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/burnrate"
cp -R "$BUNDLE" "$APP/Contents/Resources/burnrate_Burnrate.bundle"

# 4. Read the version we're shipping (might have been bumped above).
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
echo ":: shipping burnrate $VERSION"

# 5. Pick the strongest available codesigning identity.
#    Order: env override → Developer ID Application → Apple Development → self-signed → ad-hoc.
SIGN_IDENTITY="${BURNRATE_SIGN_IDENTITY:-}"
[[ -z "$SIGN_IDENTITY" ]] && SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application:/ { print $2; exit }')
[[ -z "$SIGN_IDENTITY" ]] && SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development:/ { print $2; exit }')
[[ -z "$SIGN_IDENTITY" ]] && SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Burnrate Dev/ { print $2; exit }')

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo ":: codesigning with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime \
    --sign "$SIGN_IDENTITY" \
    "$APP" 2>&1 | grep -v "replacing existing signature" || true
else
  echo ":: no codesigning identity found — using ad-hoc signature (users will see Gatekeeper warnings)"
  codesign --force --deep --sign - "$APP" 2>&1 | grep -v "replacing existing signature" || true
fi

# 6. Verify the signature.
echo ":: codesign verify"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3 || {
  echo "warning: codesign verify failed — release artefact may not launch"
}

# 7. Zip it up. Use ditto so resource forks + extended attrs survive.
mkdir -p "$DIST"
ZIP="$DIST/burnrate-$VERSION.zip"
rm -f "$ZIP"
echo ":: ditto → $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 8. Compute SHA256 (this is what goes into the Homebrew cask).
SHA256=$(shasum -a 256 "$ZIP" | awk '{ print $1 }')
echo "$SHA256  $ZIP" > "$DIST/burnrate-$VERSION.sha256"

# 9. Print the summary.
SIZE=$(du -h "$ZIP" | awk '{ print $1 }')
cat <<EOF

═══════════════════════════════════════════════════════════════════════
  burnrate $VERSION ready to ship
═══════════════════════════════════════════════════════════════════════

  Artifact:    $ZIP  ($SIZE)
  SHA256:      $SHA256
  Identity:    ${SIGN_IDENTITY:-ad-hoc}

  Next steps:

  1. Tag the release:
       git tag v$VERSION
       git push origin v$VERSION

  2. Upload to GitHub Releases:
       gh release create v$VERSION "$ZIP" --title "v$VERSION" --notes "Release $VERSION"

  3. Update Casks/burnrate.rb:
       version "$VERSION"
       sha256 "$SHA256"

  4. Commit + push the cask file change.

═══════════════════════════════════════════════════════════════════════
EOF
