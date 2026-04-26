#!/usr/bin/env bash
# Idempotent code-signing setup for burnrate dev.
#
# Why this exists: macOS Keychain ties "Always Allow" to the app's code
# signature. Unsigned/ad-hoc binaries get a fresh signature on every rebuild,
# so the user gets re-prompted constantly. Signing with a stable identity
# makes "Always Allow" persist across rebuilds.
#
# This script:
#   1. Checks if you already have a usable codesigning identity (Apple
#      Development from Xcode, or a Developer ID).
#   2. If not, creates a self-signed cert called "Burnrate Dev" and adds it
#      to your login keychain.
#   3. Prints the identity name to use in scripts/run.sh.
#
# Run once, then `scripts/run.sh` will pick it up automatically.

set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SELF_SIGNED_NAME="Burnrate Dev"

echo ":: scanning existing codesigning identities…"
existing=$(security find-identity -v -p codesigning 2>/dev/null || true)
echo "$existing"

if echo "$existing" | grep -qE 'Apple Development:|Developer ID Application:'; then
  echo
  echo "✓ You already have a codesigning identity Xcode/Apple ID provisioned."
  echo "  scripts/run.sh will pick it up automatically. Nothing else to do."
  exit 0
fi

if echo "$existing" | grep -q "\"$SELF_SIGNED_NAME\""; then
  echo
  echo "✓ Self-signed identity '$SELF_SIGNED_NAME' already installed."
  exit 0
fi

echo
echo ":: no codesigning identity found — creating a self-signed one"
echo

TMP=$(mktemp -d)
KEY="$TMP/burnrate-dev.key"
CRT="$TMP/burnrate-dev.crt"
P12="$TMP/burnrate-dev.p12"
PASS="burnrate-dev"

# Generate a self-signed certificate with the codeSigning extended-key-usage
# (so codesign accepts it as a signing identity).
openssl req -x509 -newkey rsa:2048 \
  -keyout "$KEY" -out "$CRT" \
  -days 3650 -nodes \
  -subj "/CN=$SELF_SIGNED_NAME/O=Burnrate Dev" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "keyUsage=digitalSignature" \
  >/dev/null 2>&1

# Bundle to PKCS12 for keychain import.
openssl pkcs12 -export \
  -out "$P12" \
  -inkey "$KEY" \
  -in "$CRT" \
  -password "pass:$PASS" \
  >/dev/null 2>&1

# Import into login keychain. The -T flags pre-authorise codesign + security
# to use the private key without prompting for the keychain password.
security import "$P12" \
  -k "$KEYCHAIN" \
  -P "$PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

# Tell macOS the codesign and security tools can use this private key without
# prompting. Requires unlocking the login keychain (your login password).
echo
echo ":: macOS may prompt for your login password to allow codesign to use this key."
echo "   This happens once, then never again."
security set-key-partition-list \
  -S "apple-tool:,apple:,codesign:" \
  -s -k "" \
  "$KEYCHAIN" >/dev/null 2>&1 || true

# Cleanup material on disk.
rm -rf "$TMP"

echo
echo "✓ Created self-signed identity: $SELF_SIGNED_NAME"
echo "  scripts/run.sh will pick it up automatically."
echo
echo "  On the next launch macOS will prompt once for the OAuth keychain item."
echo "  Click 'Always Allow' — and that's the last prompt you'll see."
