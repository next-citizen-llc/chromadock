#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ChromaDock.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/dist/ChromaDock-${VERSION}.dmg"

if [[ ! -d "$APP" ]]; then
  echo "Build the app first: ./scripts/build.sh" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE" "$ROOT/dist"
cp -R "$APP" "$STAGE/ChromaDock.app"
ln -s /Applications "$STAGE/Applications"

# Simple DS_Store-less UDZO disk image.
rm -f "$DMG"
hdiutil create \
  -volname "ChromaDock" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

echo "Wrote $DMG"
ls -lh "$DMG"
