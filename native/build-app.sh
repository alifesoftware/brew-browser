#!/bin/bash
# Build the SwiftUI executable with SPM, then wrap it in a .app bundle so it
# launches as a real, activatable Mac app (SPM alone produces a bare binary
# with no Info.plist, which macOS treats as a background process).
#
# Usage: native/build-app.sh [debug|release]   (default: debug)
set -euo pipefail

CONFIG="${1:-debug}"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/BrewBrowser"
APP="$HERE/BrewBrowser.app"

BINDIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$HERE/BrewBrowser.app"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BrewBrowser"

# SPM emits resource bundles (e.g. BrewBrowser_BrewBrowser.bundle) next to the
# binary. Bundle.module resolves them relative to the executable, so copy any
# alongside the binary in MacOS/ so categories.json is found at runtime.
for b in "$BINDIR"/*.bundle; do
  [ -e "$b" ] || continue
  cp -R "$b" "$APP/Contents/MacOS/"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>brew-browser</string>
    <key>CFBundleDisplayName</key><string>brew-browser</string>
    <key>CFBundleIdentifier</key><string>com.zerologic.brew-browser-native</string>
    <key>CFBundleExecutable</key><string>BrewBrowser</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> done: $APP"
echo "Launch with: open \"$APP\""
