#!/usr/bin/env bash
# brew-browser — full signed + notarized release build
#
# Usage:   source ~/.config/brew-browser/signing.env && ./tools/build/sign-and-notarize.sh
#
# Runs: cargo tauri build → notarize+staple the .dmg → verify with spctl.
# Requires: APPLE_ID, APPLE_PASSWORD, APPLE_TEAM_ID env vars set (see BUILD.md).

set -euo pipefail

# ─── Pre-flight ──────────────────────────────────────────────────────────────

cd "$(dirname "$0")/../.."   # repo root

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_PASSWORD:-}" || -z "${APPLE_TEAM_ID:-}" ]]; then
  echo "✗ Missing Apple env vars. Source your signing env first:" >&2
  echo "    source ~/.config/brew-browser/signing.env" >&2
  echo "See BUILD.md for the env file template." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
  echo "✗ No 'Developer ID Application' identity found in your keychain." >&2
  echo "  See BUILD.md, Prerequisites." >&2
  exit 1
fi

echo "▸ pre-flight ok"
echo "  apple-id:   $APPLE_ID"
echo "  team-id:    $APPLE_TEAM_ID"

# ─── Build (compile + sign + notarize .app inside) ───────────────────────────

echo
echo "▸ npm run tauri build (compile + sign + notarize .app)"
npm run tauri build

# Locate the produced .dmg (version-agnostic)
DMG="$(ls -t src-tauri/target/release/bundle/dmg/brew-browser_*_aarch64.dmg 2>/dev/null | head -1 || true)"
if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  echo "✗ build completed but no .dmg found under src-tauri/target/release/bundle/dmg/" >&2
  exit 1
fi
echo
echo "▸ .dmg produced: $DMG"

# ─── Notarize + staple the .dmg wrapper itself ───────────────────────────────

echo
echo "▸ submitting .dmg to Apple notary (waiting for ticket — typically 1-5 min)"
xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

echo
echo "▸ stapling notarization ticket to .dmg"
xcrun stapler staple "$DMG"

# ─── Verify ──────────────────────────────────────────────────────────────────

echo
echo "▸ verification"
spctl --assess --type install --verbose=4 "$DMG"
xcrun stapler validate "$DMG"

echo
echo "✓ done — $DMG is signed, notarized, stapled, and ready to ship"
ls -lh "$DMG"
