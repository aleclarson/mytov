#!/usr/bin/env bash
# Build a mytov app into a signed .app bundle and .dmg.
#   tools/package.sh examples/hello/main.tov Hello [icon.icns]
# Optional env:
#   MYTOV_VERSION=1.2.0            bundle version (default 0.1.0)
#   MYTOV_URL_SCHEMES="a,b"        CFBundleURLTypes deep-link schemes
#   MYTOV_DOC_EXT="foo,bar"        CFBundleDocumentTypes extensions
#   MYTOV_UPDATE_URL=https://…     update feed directory (update-<plat>.json)
#   MYTOV_UPDATE_PUB=key.pub       Ed25519 PEM public key baked into the app
#   MYTOV_UPDATE_KEY=key.pem       sign: also emit <App>-<ver>-<plat>.tar.gz
#                                  and update-<plat>.json in dist/
#   MYTOV_UPDATE_NOTES="text"      release notes recorded in the manifest
set -euo pipefail

ENTRY="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
APP="${2:?usage: package.sh <entry.tov> <AppName> [icon.icns]}"
ICON="${3:-}"
VERSION="${MYTOV_VERSION:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
BUNDLE="$OUT/$APP.app"

rm -rf "$BUNDLE" "$OUT/$APP.dmg"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

# Layout: the bundle executable is the helper itself (host mode) so the app
# process owns NSApplication — menus, notifications, and Apple Events like
# deep links land on it. The Tov binary sits beside it as mytov-backend,
# and a second copy of the helper as mytov-helper hosts backend windows.
HELPER_M="$OUT/mytov-helper.m"
tov run "$ROOT/tools/emit-helper.tov" "$HELPER_M" >/dev/null
clang -fobjc-arc -O2 -framework Cocoa -framework UserNotifications -o "$OUT/mytov-helper-bin" "$HELPER_M"

tov build "$ENTRY" -o "$BUNDLE/Contents/MacOS/mytov-backend"
cp "$OUT/mytov-helper-bin" "$BUNDLE/Contents/MacOS/$APP"
cp "$OUT/mytov-helper-bin" "$BUNDLE/Contents/MacOS/mytov-helper"

# URL schemes (deep links) and document extensions via env:
#   MYTOV_URL_SCHEMES="myapp,other" MYTOV_DOC_EXT="foo,bar" tools/package.sh ...
EXTRAS=""
if [ -n "${MYTOV_URL_SCHEMES:-}" ]; then
  EXTRAS="$EXTRAS  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLSchemes</key><array>"
  IFS=',' read -ra SCH <<< "$MYTOV_URL_SCHEMES"
  for sch in "${SCH[@]}"; do EXTRAS="$EXTRAS<string>$sch</string>"; done
  EXTRAS="$EXTRAS</array></dict></array>
"
fi
if [ -n "${MYTOV_DOC_EXT:-}" ]; then
  EXTRAS="$EXTRAS  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeExtensions</key><array>"
  IFS=',' read -ra EXT <<< "$MYTOV_DOC_EXT"
  for ext in "${EXT[@]}"; do EXTRAS="$EXTRAS<string>$ext</string>"; done
  EXTRAS="$EXTRAS</array><key>CFBundleTypeRole</key><string>Viewer</string></dict></array>
"
fi
if [ -n "${MYTOV_UPDATE_URL:-}" ]; then
  EXTRAS="$EXTRAS  <key>MytovUpdateFeedURL</key><string>$MYTOV_UPDATE_URL</string>
"
fi

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>dev.mytov.${APP,,}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
$EXTRAS
</dict></plist>
PLIST

if [ -n "$ICON" ]; then
  cp "$ICON" "$BUNDLE/Contents/Resources/app.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string app.icns" "$BUNDLE/Contents/Info.plist"
fi

# The public key the updater verifies archives against.
if [ -n "${MYTOV_UPDATE_PUB:-}" ]; then
  cp "$MYTOV_UPDATE_PUB" "$BUNDLE/Contents/Resources/update.pub"
fi

# Ad-hoc signature; replace with a Developer ID for distribution.
codesign --force --deep --sign - "$BUNDLE"
hdiutil create -volname "$APP" -srcfolder "$BUNDLE" -ov -format UDZO "$OUT/$APP.dmg"

# Signed update archive + manifest, next to the dmg. The feed directory
# gets the archive, then the manifest last — apps never see a manifest
# whose files are missing.
if [ -n "${MYTOV_UPDATE_KEY:-}" ]; then
  PLAT="darwin-$(uname -m)"
  ARCHIVE="$OUT/$APP-$VERSION-$PLAT.tar.gz"
  tar -czf "$ARCHIVE" -C "$OUT" "$APP.app"
  openssl pkeyutl -sign -inkey "$MYTOV_UPDATE_KEY" -rawin -in "$ARCHIVE" -out "$OUT/sig.bin"
  SIG="$(base64 -i "$OUT/sig.bin" | tr -d '\n')"
  SIZE="$(stat -f %z "$ARCHIVE")"
  rm -f "$OUT/sig.bin"
  python3 - "$OUT/update-$PLAT.json" "$VERSION" "$(basename "$ARCHIVE")" "$SIZE" "$SIG" "${MYTOV_UPDATE_NOTES:-}" <<'PY'
import json, sys, datetime
path, ver, url, size, sig, notes = sys.argv[1:7]
m = {"version": ver, "date": datetime.date.today().isoformat(),
     "archive": {"url": url, "size": int(size), "signature": sig}}
if notes: m["notes"] = notes
json.dump(m, open(path, "w"), indent=2)
PY
  echo "signed update: $ARCHIVE and $OUT/update-$PLAT.json"
fi

echo "built $BUNDLE and $OUT/$APP.dmg"
