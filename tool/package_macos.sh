#!/usr/bin/env bash
# Builds a release "Serial Monitor.app" and packs it into a disk image:
#   dist/SerialMonitor-<version>-macos.dmg
# Run from anywhere:  tool/package_macos.sh
#
# Optional, for builds you hand to other people (needs an Apple Developer account):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"  sign with that certificate
#   NOTARY_PROFILE=<name>   also notarize, using credentials saved once with
#                           xcrun notarytool store-credentials <name>
# Without them the app is ad-hoc signed: fine on the Mac that built it; on
# another Mac, see "Opening an unsigned build" in docs/PACKAGING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "$(uname)" == "Darwin" ]] || { echo "Run this on macOS." >&2; exit 1; }

version=$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' pubspec.yaml)
app="build/macos/Build/Products/Release/Serial Monitor.app"
out="dist/SerialMonitor-$version-macos.dmg"

flutter build macos --release

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements macos/Runner/Release.entitlements \
    --sign "$SIGN_IDENTITY" "$app"
fi
codesign --verify --deep --strict "$app"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Serial Monitor.app"
ln -s /Applications "$stage/Applications"

mkdir -p dist
rm -f "$out"
hdiutil create -quiet -volname "Serial Monitor $version" -srcfolder "$stage" \
  -fs HFS+ -format UDZO "$out"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --timestamp --sign "$SIGN_IDENTITY" "$out"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$out" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$out"
  fi
fi

echo
echo "Wrote $out"
