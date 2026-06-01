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

BINDIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BINDIR/BrewBrowser"
APP="$HERE/BrewBrowser.app"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BrewBrowser"

# App icon — the real brew-browser icon (1024px .icns, shared with the Tauri
# app). Gives the .app a proper Dock/Finder/⌘-Tab icon instead of the generic
# placeholder. Referenced by CFBundleIconFile below.
if [ -f "$HERE/AppIcon.icns" ]; then
  cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# SPM emits resource bundles (e.g. BrewBrowser_BrewBrowserKit.bundle) carrying
# categories.json / enrichment.json / AppIcon.icns. `Bundle.module` resolves
# them relative to the executable, searching Contents/Resources too — so we copy
# them into Resources/ (NOT MacOS/). Two reasons over the old MacOS/ placement:
#   1. Resources/ is the codesign-valid home for nested bundles; a bundle in
#      MacOS/ makes `codesign --deep` reject the app ("bundle format
#      unrecognized") because it expects a Mach-O there, not a directory.
#   2. SwiftPM resource bundles ship flat (no Info.plist), which codesign also
#      rejects — so we synthesize a minimal Info.plist in each, making the app
#      sign-clean for a future notarized release.
for b in "$BINDIR"/*.bundle; do
  [ -e "$b" ] || continue
  bname="$(basename "$b")"
  dest="$APP/Contents/Resources/$bname"
  cp -R "$b" "$dest"
  # Synthesize a minimal Info.plist if SwiftPM didn't emit one, so codesign
  # treats it as a real bundle.
  if [ ! -f "$dest/Info.plist" ]; then
    # bundle id: strip .bundle, lowercase — e.g. com.zerologic.brew-browser-native.BrewBrowser_BrewBrowserKit
    bid="com.zerologic.brew-browser-native.${bname%.bundle}"
    cat > "$dest/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${bname%.bundle}</string>
    <key>CFBundleIdentifier</key><string>${bid}</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
</dict>
</plist>
PLIST
  fi
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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> done: $APP"
echo "Launch with: open \"$APP\""
