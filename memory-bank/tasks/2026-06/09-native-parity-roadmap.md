# 09 — Native ← Tauri parity roadmap (the remaining gap)

**Date:** 2026-06-06
**Branch:** `experiment/native-swift-liquid-glass`
**Mission:** bring native (SwiftUI, all Apple-native primitives) up to the Tauri
build's functionality. Tauri = source-of-truth spec; native = destination.

Derived from a full side-by-side feature sweep of both builds (Activity already
done, task 08). Items grouped into **bundles** ordered by leverage. Each item
lists the Tauri source and the native destination.

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

## Bundle C — Self-updater  ⚠️ NEEDS USER INPUT
Tauri: `update/*` commands, `SettingsSectionUpdates.svelte`, `UpdateIndicator.svelte`.
- C1. Decision pending: real **Sparkle** integration (SPM dep + appcast + EdDSA
  signing keys + hosting) vs **UI-only** (check/notify + "download on website").
  Sparkle needs signing infra the agent can't self-provision → confirm scope.
- C2. Whatever scope: wire the Updates settings tab + a titlebar "update available"
  affordance.

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

## Open questions for the user
1. **Self-updater (C)**: full Sparkle, or UI + notify only (defer real self-update)?
2. Anything in **Bundle F** you'd rather skip as non-native?
