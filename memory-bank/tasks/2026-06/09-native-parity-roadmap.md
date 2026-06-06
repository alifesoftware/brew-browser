# 09 — Native ← Tauri parity roadmap (the remaining gap)

**Date:** 2026-06-06
**Branch:** `experiment/native-swift-liquid-glass`
**Mission:** bring native (SwiftUI, all Apple-native primitives) up to the Tauri
build's functionality. Tauri = source-of-truth spec; native = destination.

Derived from a full side-by-side feature sweep of both builds (Activity already
done, task 08). Items grouped into **bundles** ordered by leverage. Each item
lists the Tauri source and the native destination.

## STATUS — ALL BUNDLES LANDED (2026-06-06)
All six bundles implemented, built clean, committed + pushed on
`experiment/native-swift-liquid-glass`:
- A keyboard + ⌘K palette → `b9f5cfd`
- B vulnerability surfacing → `7f49aff`
- D enrichment / Discover → `21fb4a5`
- E upgrade sheet + GitHub detail → `8c54da4`
- F About / status row / toasts / window state → `7105733`
- C Sparkle self-updater → `f0f0d41`
**Only remaining = the two human-run Sparkle items** (real `SUPublicEDKey` + host
the appcast/zip on `brew-browser.zerologic.com`). See "Releasing native (Sparkle)"
at the bottom. Everything builds + functions today.

## Execution model
- **Single compiled codebase** → Swift edits are serialized (parallel edits to
  `AppModel.swift`/`ContentView.swift` would conflict + break the build).
- **Loop**: one item (or tight sub-group) per iteration → implement → `swift build`
  → fix → mark done → next. `native/build-app.sh` after each bundle.
- **Agent team + agents**: research/spec extraction from Tauri and design can fan
  out in parallel; the actual Swift edit + build is serialized by the orchestrator.
- Verify per bundle; user tests via screenshots. Commit per bundle.

---

## Bundle A — Keyboard shortcuts + Command palette (highest "native-pro" leverage)
Tauri: `src/routes/+page.svelte:46-128` (global keys), `CommandPalette.svelte`,
`Sidebar.svelte:35-43` (⌘0–6 map).
Native dest: new `Commands`/`CommandGroup` in `BrewBrowserApp.swift`; new
`CommandPaletteView.swift`; `AppModel` selection + drawer + refresh hooks.
- A1. Section nav ⌘0–6 (Dashboard…Activity) via `.commands` `CommandGroup`.
- A2. ⌘L toggle Activity drawer; global ⌘R refresh; ⌘⇧L cycle theme; `/` focus
  search; Esc chain (close inspector → palette).
- A3. **⌘K command palette** — sheet/overlay; sources: installed (top 8), index
  (`brew search`, debounced), commands (open sections, toggle drawer, refresh).
  Stock `.sheet` + `List` + `.searchable` or custom field. (Mirror
  `CommandPalette.svelte`.)

## Bundle B — Vulnerability surfacing (native scans; only shows it in detail)
Tauri: `Dashboard.svelte:818-912` (Exposure card), `Library.svelte` Vulnerable
pill + `PackageRow.svelte` severity dot, `Sidebar.svelte:165-194` vuln badge,
`PackageDetail.svelte:997-1138` (clickable advisory ids + Upgrade-to-fix).
Native dest: `AppModel` (scan-all + severity index), `DashboardView`,
`ContentView` Library filter, `PackageDetailView` security card.
- B1. **Scan-all** in AppModel (currently per-detail only) + a name→maxSeverity map.
- B2. Library "Vulnerable" filter pill (was deferred, `AppModel.swift:32-33`) +
  severity dot column on rows.
- B3. Dashboard **Exposure card** (per-severity counts, Scan now, View vulnerable).
- B4. Sidebar/section vuln badge (native sidebar = stock `.badge`; surface count).
- B5. Detail security card: clickable CVE/GHSA/OSV → canonical advisory; "Upgrade
  to fix" when installed < fixedIn.

## Bundle C — Self-updater (DECISION: **Sparkle**, 2026-06-06)
Tauri: `update/*` commands, `SettingsSectionUpdates.svelte`, `UpdateIndicator.svelte`.
User chose true in-app self-update via **Sparkle 2** (the standard for non-MAS
macOS apps; SwiftUI-compatible). MAS is out (sandboxing blocks shelling to brew).
- C1. Add Sparkle via SPM to `native/Package.swift`; create an updater controller
  (`SPUStandardUpdaterController`) wired into the app + a `Settings → Updates` tab
  (Check now / last-checked / auto-check daily) and a titlebar "update available"
  affordance (mirror `UpdateIndicator.svelte`).
- C2. `Info.plist`: `SUFeedURL` + `SUPublicEDKey` + `SUEnableAutomaticChecks`.
  Add an `appcast.xml` generation step (Sparkle `generate_appcast`).
- **Host (decided 2026-06-06): mirror the Tauri updater** — Tauri's updater feed
  is the PUBLIC domain `https://brew-browser.zerologic.com/updater.json`
  (`src-tauri/tauri.conf.json:34`), served by the same Caddy that fronts
  `/enrichment/*` + `/trending-history/*`. The private build-host IP appears in
  ZERO committed files; keep it that way. Sparkle mirror = same public host, new
  path:
  - `SUFeedURL` = `https://brew-browser.zerologic.com/appcast.xml` (public domain,
    safe to commit into Info.plist).
  - Artifacts: notarized `.app` zip under a sibling path on the same domain.
  - Caddy: one `handle_path /appcast.xml` + a static path for the zip, mirroring
    the existing trending/enrichment blocks.
- **BLOCKED on user (provision, can't be self-generated):**
  1. **Sparkle EdDSA keypair** via `generate_keys` — NOTE Tauri signs with
     minisign (its `tauri.conf.json` pubkey); Sparkle uses ed25519, so the key
     does NOT carry over. Public key → Info.plist `SUPublicEDKey`; private key
     stays in the login Keychain (never committed).
  2. Caddy path + actually hosting `appcast.xml` + the notarized zip on
     `brew-browser.zerologic.com`; and notarizing the `.app`.
  Build everything else with the public domain; leave the key + hosting as
  clearly-marked TODO placeholders.

## Bundle D — Enrichment / Discover
Tauri: `Discover.svelte` (tile grid, recent searches, stale banner),
`Dashboard.svelte:524-553` (catalog freshness strip), `PackageDetail.svelte`
"Wrong?" + `IssueModal.svelte`.
Native dest: `DiscoverView`, `DashboardView`, `PackageDetailView`, `AppModel`.
- D1. **"Wrong?" corrections** on enriched fields + categories → prefilled issue
  (reuse `ReportIssue.swift` pattern / device-flow issue sheet).
- D2. Discover **category tile grid** (icon/label/count) replacing/augmenting the
  current Picker; click → filter.
- D3. **Recent-searches** chips in Discover.
- D4. **Catalog-freshness strip** (Dashboard) + **stale-catalog banner** (Discover)
  with one-click "Refresh from brew.sh".

## Bundle E — Bulk actions + GitHub detail
Tauri: `UpgradeModal.svelte`, `PackageDetail.svelte:1215-1344` (GitHub card+actions).
Native dest: new `UpgradeSheet.swift`; `PackageDetailView` GitHub card; `GitHubService`.
- E1. **Curated upgrade sheet** ("Choose…") — multi-select outdated (pinned
  excluded), select/deselect all → `brew upgrade <names>`. Native "Choose…"
  currently just filters Library.
- E2. GitHub detail: **Unstar/Unwatch** toggle states (verify `GitHubService` has
  unstar/unwatch), **archived-repo** warning, **license-mismatch** warning.

## Bundle F — Minor / cosmetic (native-idiomatic equivalents; skip redundant)
- F1. **AboutModal** equivalent — native-idiomatic About (brand + version + donate
  + credits). Tauri has both Settings→About and a modal; native has only the tab.
  (Consider a custom About window or `.appInfo`.)
- F2. Sidebar **brew-status row** (health dot + label + click-to-reprobe).
- F3. **Toast system with action buttons** (e.g. "Re-authorize" scope-fix). Native
  uses macOS notifications; decide if an in-window transient is wanted.
- F4. Window size/position persistence (Tauri PR #17) — confirm not already covered
  by macOS state restoration; add `.defaultPosition`/scene storage if needed.
- (Skip: titlebar theme dropdown — Settings→Appearance already covers theme the
  native way.)

---

## Cross-cutting rules
- All native, stock SwiftUI/AppKit primitives; no chrome/material overrides.
- Reuse: `ReportIssue.swift`, `PackageIcon`/`KindPill`/`Chip`, the `startJob`
  engine, `AppSettings` gating helpers (`vulnerabilityScanningAllowed`,
  `githubAllowed`, `networkAllowed`, `aiFeaturesVisible`).
- Gate every network feature on Offline Mode + its toggle (mirror Tauri).
- No private host names in committed files.

## Releasing native (Sparkle)

Bundle C wired Sparkle 2 into the native build (`Package.swift` dep,
`UpdaterController.swift`, the Settings → Updates tab, the titlebar pill, and the
`SUFeedURL` / `SUPublicEDKey` / `SUEnableAutomaticChecks` / `SUScheduledCheckInterval`
keys in `build-app.sh`'s Info.plist).

**Done (2026-06-06):**
- ✅ **Keypair generated.** `generate_keys` run; the ed25519 PUBLIC key
  `OoRc2WZfiHX21nhhm/inmv5l282Ob97GBwx+fZoML/E=` is baked into `build-app.sh`'s
  `SUPublicEDKey` (committed — public by design). The PRIVATE key lives in the
  maintainer Mac's login Keychain (never committed). Tauri's minisign key does
  NOT carry over — Sparkle uses ed25519.
- ✅ **One-command release script** `native/release.sh`: build(release) →
  Developer ID sign (hardened runtime, inside-out incl. Sparkle.framework) → zip
  → `notarytool submit --wait` → staple → re-zip → `generate_appcast`
  (`--download-url-prefix https://brew-browser.zerologic.com/native/`) → `appcast.xml`.

**Operator steps to actually ship a release (need your Apple creds + host):**
1. Bump `CFBundleShortVersionString` + `CFBundleVersion` in `native/build-app.sh`.
2. `DEVELOPER_ID_APP="Developer ID Application: … (TEAMID)" NOTARY_PROFILE=<profile> native/release.sh`
   (create the notary profile once: `xcrun notarytool store-credentials …`).
   Outputs `native/dist/BrewBrowser-<ver>.zip` + `native/dist/appcast.xml`.
3. **Host (mirror the Tauri updater):** serve `appcast.xml` + the zip from
   `brew-browser.zerologic.com` behind the same Caddy that fronts `/enrichment/*`
   + `/trending-history/*`. The app's `SUFeedURL` is
   `https://brew-browser.zerologic.com/appcast.xml`; the zips sit under `/native/`.
   Add a block like (public domain only — no private host names anywhere):
   ```
   handle_path /appcast.xml      { root * $OUT_DIR; file_server }
   handle_path /native/*         { root * $OUT_DIR; file_server }
   ```
   then upload `native/dist/*` to `$OUT_DIR` (rsync/scp from local ops).

That's the whole loop: in-app updater is complete; a release is `release.sh` +
upload.

## Open questions for the user
1. **Self-updater (C)**: full Sparkle, or UI + notify only (defer real self-update)?
   → Resolved 2026-06-06: full Sparkle. Implemented in Bundle C.
2. Anything in **Bundle F** you'd rather skip as non-native?
