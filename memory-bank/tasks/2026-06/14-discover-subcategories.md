# 14 — Discover sub-categories (feature #6) + feature-request batch

**Date:** 2026-06-13
**Branch:** `feat/feature-requests` (off `main`; PR #73 already merged)

## Context

`feat/feature-requests` works through the 6 Reddit feature requests, one numbered
commit per feature, **both shells** (native Swift + Tauri/Svelte) in data-contract
parity each time (parity charter — `decisions.md` 2026-06-01). #1–#5 were committed
by prior sessions; this doc records **feature #6 (Discover sub-categories)**, which
was completed, parity-corrected, and verified this session (#6 still uncommitted).

| # | Feature | Commit |
|---|---|---|
| 1 | reverse dependencies ("Required by") in package detail | `9c1edfa` |
| 2 | deprecated / disabled indicators on packages | `9fa7d1a` |
| 3 | Manual vs Dependency filter in the Library | `d9663b3` |
| 4 | per-package on-disk size in detail | `695e6ff` |
| 5 | Recent Homebrew changes | deferred — `f0bf50e` was activity-derived, not the requested catalog/local-delta feature |
| 6 | **Discover sub-categories (this doc)** | uncommitted |

## Objective

Add a second-level drill-down to the Discover browse view. Recon verdict:
`categories.json` is strictly **flat** — there is no nested/sub-category field and
the offline categorizer emits a single level. The one genuine second-level signal
already in the data is **multi-label membership** (~3463 of 15974 tokens carry >1
category). So within a selected category X, members are sub-grouped by their OTHER
co-assigned category slugs — a 100%-data-derived drill-down, no commands, no
subprocess, no catalog refetch.

Honest weakness, surfaced in the UI (never hidden): co-occurrence does not cleanly
partition a category (developer-tools is ~65% solo). Every category therefore needs
a **"General <Label>"** bucket (members carrying only the selected slug), frequently
the largest group. Labels read **"<Selected> + <Other>"** / **"General <Selected>"**
and an info popover disclaims that this is a grouping aid, not a taxonomy tree.

## What changed

### Derivation (parity core — both shells must agree byte-for-byte)
- **Tauri:** `src/lib/util/subcategories.ts` (new) — `subgroupsFor(data, selectedSlug, excludeCasks)`.
  Store pass-through `categories.subgroupsInCategory(slug)` threads the in-memory
  data + the Linux cask gate (`isLinux`).
- **Native:** `Categories.swift` — `CategoryCatalog.subgroups(in:)` + `memberInSubgroup(...)`
  drill-down predicate + `CategorySubgroup`/`SubgroupMember` types.
- Agreed contract: sub-group **key** (co-occurring slug, or `__general__`
  sentinel for solo), **label** form, **membership** (a member with N other slugs
  appears under each, deduped within a bucket not across; solo → general),
  **ordering** (descending item count, tie-break key slug ascending, general pinned
  last), and the **Linux cask exclusion** (Tauri only; native is macOS-only so always
  includes casks).

### Parity fix (the bug found + fixed this session)
- TS was **not** excluding `uncategorized` as a co-occurring bucket while Swift was
  (`.filter { $0 != slug && $0 != "uncategorized" }`). Real, observable divergence:
  `translate-shell` is tagged `[terminal, uncategorized]`, so browsing **Terminal**
  spawned a phantom "Terminal + Uncategorized" bucket on web that native never
  produced. Fixed TS (`UNCATEGORIZED_SLUG` const + guard) so a `[X, uncategorized]`
  member folds into **General X** on both shells. Added 2 TS tests mirroring native's
  `generalBucketHoldsSoloMembers` / `uncategorizedSplitsByRealCoOccurrence`.

### UI wiring
- **Tauri** `Discover.svelte`: sub-grouped sections (sticky per-bucket header + count)
  via a shared `browseRow` snippet (the 5-column row markup, deduped out of the flat
  list); `InfoButton` "About sub-categories". Sub-grouping shows **only** for a single
  selected category with no search narrowing; multi-chip/search views stay flat. A
  lone general bucket is suppressed (falls through to the flat list).
- **Native** `DiscoverView.swift`: horizontal sub-group **chip strip** ("All" + one
  chip per bucket) above the table; tapping narrows the table to one sub-group.
  `AppModel.swift`: `discoverSubgroups` (gated to single category + empty query) +
  `discoverSubgroupKey` (cleared when category changes) + the drill-down filter in the
  row pipeline. Same single-category/no-search rule; lone-general suppressed.

## Files
- Tauri: `src/lib/util/subcategories.ts` (new), `src/lib/util/subcategories.test.ts` (new),
  `src/lib/stores/categories.svelte.ts`, `src/lib/components/Discover.svelte`.
- Native: `native/Sources/BrewBrowserKit/Categories.swift`,
  `native/Sources/BrewBrowserKit/AppModel.swift`,
  `native/Sources/BrewBrowserKit/DiscoverView.swift`,
  `native/Tests/BrewBrowserKitTests/CategoriesTests.swift`.

## Outcome
- ✅ Tauri: `npx vitest run` — 35 passing (12 in `subcategories.test.ts`); `npm run check`
  0 errors (2 pre-existing unrelated CSS warnings in `SettingsSectionGitHub.svelte`).
- ✅ Native: `swift test` — 124 passing (10 in `CategorySubgroups`); build clean.
- ✅ Parity locked: the fixed parity fixture asserts identical ordered keys, labels, and
  membership across both shells from the same input.

## Versioning note
This batch ships as **Tauri `0.6.0` / native `0.2.0`** — split tracks (each shell
versions by its own release history; native only ever shipped 0.1.0, so 0.6.0 would
invent releases that never existed). Supersedes the old `0.5.2 / 0.1.1` proposal.
Bumps already applied by a parallel docs pass (package.json / Cargo.toml /
tauri.conf.json → 0.6.0; `native/build-app.sh` CFBundleShortVersionString → 0.2.0).
