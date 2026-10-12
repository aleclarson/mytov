#!/usr/bin/env bash
# Build a mytov app into a signed .app bundle and .dmg.
#   tools/package.sh examples/hello/main.tov Hello [icon.icns]
set -euo pipefail

ENTRY="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
APP="${2:?usage: package.sh <entry.tov> <AppName> [icon.icns]}"
ICON="${3:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
BUNDLE="$OUT/$APP.app"

rm -rf "$BUNDLE" "$OUT/$APP.dmg"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

tov build "$ENTRY" -o "$BUNDLE/Contents/MacOS/$APP"

# Precompiled helper beside the executable — helperPath() finds it there.
HELPER_M="$OUT/mytov-helper.m"
tov run "$ROOT/tools/emit-helper.tov" "$HELPER_M" >/dev/null
clang -fobjc-arc -O2 -framework Cocoa -framework UserNotifications \
  -o "$BUNDLE/Contents/MacOS/mytov-helper" "$HELPER_M"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>dev.mytov.${APP,,}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

if [ -n "$ICON" ]; then
  cp "$ICON" "$BUNDLE/Contents/Resources/app.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string app.icns" "$BUNDLE/Contents/Info.plist"
fi

# Ad-hoc signature; replace with a Developer ID for distribution.
codesign --force --deep --sign - "$BUNDLE"
hdiutil create -volname "$APP" -srcfolder "$BUNDLE" -ov -format UDZO "$OUT/$APP.dmg"
echo "built $BUNDLE and $OUT/$APP.dmg"
