#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/ChromaDock.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD"

echo "Compiling divider helper…"
swiftc -O \
  -sdk "$SDK" \
  -target "$TARGET" \
  -framework AppKit -framework ImageIO \
  "$ROOT/Sources/ChromaDock/LineStyle.swift" \
  "$ROOT/Sources/ChromaDock/WallpaperSampler.swift" \
  "$ROOT/Sources/ChromaDock/DividerMark.swift" \
  "$ROOT/Sources/ChromaDock/Paths.swift" \
  "$ROOT/Sources/ChromaDock/Models.swift" \
  "$ROOT/Sources/DividerHelper/main.swift" \
  -o "$APP/Contents/MacOS/ChromaDockDivider"

echo "Compiling ChromaDock…"
swiftc -O \
  -sdk "$SDK" \
  -target "$TARGET" \
  -framework SwiftUI -framework AppKit -framework ServiceManagement -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT/Sources/ChromaDock/"*.swift \
  -o "$APP/Contents/MacOS/ChromaDock"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

echo "Signing…"
codesign --force --sign - --identifier llc.nextcitizen.ChromaDock.divider \
  "$APP/Contents/MacOS/ChromaDockDivider"
codesign --force --sign - --identifier llc.nextcitizen.ChromaDock \
  --entitlements "$ROOT/Resources/ChromaDock.entitlements" \
  "$APP"

echo "Built $APP"
/usr/bin/codesign -dv --verbose=2 "$APP" 2>&1 | head -20
