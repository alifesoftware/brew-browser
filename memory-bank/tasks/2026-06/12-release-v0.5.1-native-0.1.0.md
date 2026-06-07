# 12 — Release: Tauri 0.5.1 + native 0.1.0 (first native release)

**Date:** 2026-06-07
**Status:** SHIPPED + verified. Both builds live, auto-update feeds live, smoke-tested.

First time both builds shipped together. Tag `v0.5.1` on `main`.

## What shipped
- **Tauri 0.5.1** — GitHub Release `v0.5.1`, in-app updater (`updater.json` → 0.5.1)
  live + serving existing users, cask bumped (`msitarzewski/homebrew-brew-browser`
  `c8c7f50`, version 0.5.1 + sha256 of the .dmg).
- **Native 0.1.0** — FIRST native release. Sparkle appcast live for real
  (`brew-browser.zerologic.com/appcast.xml` + zip under `/native/`).
- Content: progress counts (#57), upgrade-all firehose fix, category→Library
  (#58), GitHub sign-in reliability (combined keychain), launch hydration, window
  fixes (#17/#19/#8/#10), fresh bundled catalog. See `docs/release-notes/0.5.1.md`.

## Release artifacts (on the v0.5.1 GitHub release — 5 assets)
- `brew-browser_0.5.1_aarch64.dmg` (Tauri install) + `…app.tar.gz` (+`.sig`) (Tauri updater payload)
- `BrewBrowser-0.1.0.dmg` (native install) + `BrewBrowser-0.1.0.zip` (native Sparkle payload)

## ✅ Verified
Tauri updater.json=0.5.1, all artifact URLs 200, native appcast 200, cask 0.5.1.
**GUI keychain smoke test PASSED on the signed build** — sign-in persists (the
combined-credential fix is confirmed end-to-end, not just in unit tests).

## Deploy gotchas (read before the NEXT deploy)
1. **Sparkle `generate_appcast` caches updates** in `~/Library/Caches/Sparkle_generate_appcast/`
   and KEEPS appcast entries whose zip is gone ("removed 0 old updates"). A stale
   `BrewBrowser-0.2.0.zip` test build resurrected itself. Before regenerating:
   clear `dist/` of old zips, delete `dist/appcast.xml`, AND `rm -rf ~/Library/Caches/Sparkle_generate_appcast`.
2. **`gh release upload file#label` sets the asset LABEL, not the URL name.** The
   updater.json URL is `brew-browser_<v>_aarch64.app.tar.gz`, so COPY the artifact
   to that exact filename before uploading (don't rely on `#`). Mismatch = updater 404.
3. **Freshly-uploaded GitHub release assets 404 for ~30–60s** (CDN provisioning) —
   not an error; re-check.
4. **Native = two distribution channels:** Sparkle (zip + appcast on the host, for
   auto-update) AND a `.dmg` on the GitHub release (for first-install). `release.sh`
   now builds the `.dmg` too (Developer-ID signed + notarized + stapled).
5. **`zsh` aborts a whole `rm` line on an unmatched glob** (`dist/*.delta`) — use
   separate `rm -f` per pattern.
6. Build host deploy: `rsync` WITHOUT `--delete` (shared root holds updater.json +
   appcast + landing). zip → `Sites/brew-browser/native/`, appcast → root.

## Runbook (canonical, both builds)
Tauri: `source ~/.config/brew-browser/signing.env && ./tools/build/sign-and-notarize.sh`
→ tag → `gh release create` (copy .app.tar.gz to versioned name) →
`tools/release/publish-manifest.sh <v>` → rsync updater.json → cask bump.
Native: `DEVELOPER_ID_APP=… NOTARY_PROFILE=brew-browser native/release.sh` →
upload zip+appcast to host → attach .dmg to the GitHub release.
