#!/bin/zsh
# Builds Headroom.app from a clean checkout. Requires only Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ swift build -c release"
swift build -c release

echo "▸ app icon"
ICONSET=.build/AppIcon.iconset
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o .build/AppIcon.icns

echo "▸ bundle"
APP=Headroom.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Headroom "$APP/Contents/MacOS/Headroom"
cp Info.plist "$APP/Contents/Info.plist"
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ ad-hoc codesign"
codesign --force --deep --sign - "$APP"

echo "✓ built $APP"
