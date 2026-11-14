#!/usr/bin/env bash
# One-time setup on macOS: generates the native runner folders and lets the
# app reach serial ports. Run from anywhere:  tool/bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Commit or stash your changes first: this script restores tracked files." >&2
  exit 1
fi

flutter create --platforms=macos,windows --project-name serial_monitor --org dev.richmr .
# flutter create may rewrite files that already exist; put ours back.
git checkout -- .

if [[ "$(uname)" == "Darwin" ]]; then
  # The App Sandbox blocks serial devices, the file picker and the loopback
  # upload hook. This is a local development tool, so turn it off.
  for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
    /usr/libexec/PlistBuddy -c "Set :com.apple.security.app-sandbox false" "$f"
  done
fi

flutter pub get
echo
echo "Ready. Run it with:  flutter run -d macos"
echo "Commit the generated macos/ and windows/ folders."
