#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from a source 1024x1024 PNG.
#
# Run this whenever the brand image changes. Otherwise the existing
# Resources/AppIcon.icns is committed and reused on every build.
#
# Usage:
#   scripts/build-app-icon.sh                   # uses default source
#   scripts/build-app-icon.sh /path/to/src.png  # uses custom source

set -euo pipefail

cd "$(dirname "$0")/.."

DEFAULT_SOURCE="branding/logo/main_macos Exports/main_macos-iOS-Default-1024x1024@1x.png"
SOURCE="${1:-$DEFAULT_SOURCE}"
OUTPUT="Resources/AppIcon.icns"

if [[ ! -f "$SOURCE" ]]; then
  echo "error: source not found: $SOURCE" >&2
  exit 1
fi

echo ":: building AppIcon.icns from $SOURCE"

TMP=$(mktemp -d)
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

sips -z 16 16     "$SOURCE" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$SOURCE" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$SOURCE" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$SOURCE" "$ICONSET/icon_512x512@2x.png"

mkdir -p "$(dirname "$OUTPUT")"
iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$TMP"

SIZE=$(du -h "$OUTPUT" | awk '{ print $1 }')
echo "✓ wrote $OUTPUT ($SIZE)"
echo "  next: scripts/run.sh or scripts/release.sh will pick this up automatically"
