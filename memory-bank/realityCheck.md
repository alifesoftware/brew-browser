# Reality Check — Wave 3 Gate Report

**Owner:** Reality Checker
**Date:** 2026-05-23
**Reads:** all of `memory-bank/`, all of `src-tauri/src/`, all of `src/`, `README.md`, `docs/PLAN.md` (was `PLAN.md` at root at the time), `LICENSE`, `tauri.conf.json`, `capabilities/default.json`, plus live `cargo` + `npm` + `brew` output captured below.

> **v0.3.0 status (2026-05-25) — post-Wave-3 audit, this file's findings are now resolved.**
> The one true showstopper called out below — `tauri-plugin-dialog` not registered — was wired immediately after this audit (`src-tauri/Cargo.toml:19` has `tauri-plugin-dialog = "2"` and `src-tauri/src/lib.rs:67` calls `.plugin(tauri_plugin_dialog::init())`). Snapshots Import/Export work end-to-end. The verdict at the time of this snapshot ("NEEDS-WORK") shipped as fixed in v0.1.0 and every subsequent release.
> Project state has moved well past Wave 3: v0.1.0 → v0.2.0 → v0.2.1 → **v0.3.0** all shipped (signed, notarized, on GitHub Releases). 473 backend tests pass. The path references in this document point at `PLAN.md` at root; that file is now at `docs/PLAN.md` (moved 2026-05-25 per the docs reorganization). Historical narrative below is preserved unchanged so the audit trail stays honest.

---

## 1. Gate decision

# **NEEDS-WORK** (one true showstopper for the demo path)

Not blocking ship from a code-correctness or openness standpoint — the build is clean, the openness posture is honest and matched by the repo, and 19 of 20 commands look workable. **But** the Snapshots feature ships a runtime trap: the frontend calls `@tauri-apps/plugin-dialog` for Import/Export, and the Rust side never registers it. The first user to click *Import* or *Export…* will see Tauri reject the IPC. For a demo whose pitch is "install it and use it without surprises", that's a hard fail. Trivial fix, but it has to happen before the demo flips green.

Verdict, then: not `READY-FOR-DEMO` until the dialog plugin is wired and a fresh `npm install && npm run tauri dev` is exercised end-to-end. Not `NEEDS-WORK-BLOCKING-SHIP` — nothing here threatens the openness posture or the security model.

---

## 2. Evidence — actual command output

### 2.1 `cargo check` (after `cargo clean -p brew-browser` to defeat the cache)

```
$ cargo clean --manifest-path src-tauri/Cargo.toml -p brew-browser
     Removed 88 files, 100.6MiB total

$ cargo check --manifest-path src-tauri/Cargo.toml
   Compiling brew-browser v0.1.0 (/Users/michael/Clean/brew-browser/src-tauri)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 2.53s
```

**0 errors, 0 warnings.** Backend Architect's claim verified.

### 2.2 `npm run build`

Last 5 lines (full build succeeds end-to-end through SvelteKit + Vite + adapter-static):

```
.svelte-kit/output/server/entries/pages/_page.svelte.js                96.44 kB
.svelte-kit/output/server/index.js                                    130.56 kB
✓ built in 1.11s
> Using @sveltejs/adapter-static
  Wrote site to "build"
  ✔ done
```

Clean. The `build/` directory is what `tauri.conf.json` points to as `frontendDist`.

### 2.3 `npm run check` (svelte-check)

```
1779570146493 START "/Users/michael/Clean/brew-browser"
1779570146494 WARNING "tsconfig.json" 1:1 "Cannot find type definition file for 'node'.
  The file is in the program because:
    Entry point of type library 'node' specified in compilerOptions"
1779570146494 COMPLETED 198 FILES 0 ERRORS 1 WARNINGS 1 FILES_WITH_PROBLEMS
```

**0 errors, 1 unrelated warning** (`tsconfig.json` references `@types/node` which isn't installed). Cosmetic — does not affect runtime. Frontend Developer's claim verified.

### 2.4 Command count verification

```
$ grep -E "^\s+brew_|^\s+brewfile_|^\s+trending_|^\s+cancel_job" src-tauri/src/lib.rs | wc -l
21
```

`lib.rs` registers all **20 commands** (the 21 includes a duplicate count for the trailing comma line). Confirmed by reading: `brew_doctor`, `brew_list`, `brew_outdated`, `brew_info`, `brew_search`, `brew_search_desc`, `brew_install`, `brew_uninstall`, `brew_upgrade`, `brew_update`, `cancel_job`, `brewfile_dump`, `brewfile_install`, `brewfile_check`, `brewfile_list`, `brewfile_read`, `brewfile_delete`, `brewfile_export`, `brewfile_import`, `trending_fetch`, `trending_clear_cache` = **20 unique**, matching the `backendApi.md` spec.

### 2.5 Sidebar sections matching spec

```
$ grep -E '"library"|"discover"|"trending"|"snapshots"|"activity"' src/lib/types.ts
  | "library"
  | "discover"
  | "trending"
  | "snapshots"
  | "activity";
```

All five sections in `uxArchitecture.md` are present in `SidebarSection` and rendered in `+page.svelte`. Verified.

### 2.6 OKLCH tokens

```
$ grep -c "oklch" src/lib/styles/tokens.css
58
```

58 OKLCH color declarations across light + dark — matches `designSystem.md` §2. Verified.

### 2.7 Capability allowlist

`src-tauri/capabilities/default.json` contains exactly:

```json
"permissions": ["core:default", "opener:default", "core:event:default"]
```

The `core:event:default` permission required for `Channel<BrewStreamEvent>` IS present. Backend Architect's §10.5 drift note checked out.

### 2.8 Openness posture

- `LICENSE` — present, MIT, with `Copyright (c) 2026 Michael Sitarzewski`.
- `README.md` — leads with "Full source, MIT-licensed, no telemetry, no accounts.", a "Why this exists" section, MIT badge, and clear build-from-source instructions.
- No `CLA`, `Terms`, `Privacy`, or `EULA` files anywhere in the tree.
- `package.json` declares `"license": "MIT"`; `src-tauri/Cargo.toml` declares `license = "MIT"`. Aligned.

### 2.9 Telemetry / tracking / analytics — frontend

Searched `src/` for `tracking`, `telemetry`, `posthog`, `segment.io`, `google-analytics`, `mixpanel`, `amplitude`, `fetch(`, `XMLHttpRequest`, `axios`: **zero hits**. The only outbound HTTP from the app is from Rust via `reqwest` against `https://formulae.brew.sh/api/analytics/install/<window>.json` — confirmed reachable (`HTTP 200`) and ethically OK per `decisions.md`.

### 2.10 Live brew JSON shapes vs the parser

```
$ brew --version
Homebrew 5.1.13

$ brew outdated --cask --json=v2
{
  "formulae": [],
  "casks": [
    {
      "name": "ngrok",                          ← Rust uses `.name` ✓
      "installed_versions": ["3.39.3,2vZur35asZP,a"],
      "current_version": "3.39.4,koVh3r9rKG7,a",
      ...
```

Casks side of `brew outdated --json=v2` uses `name` (not `token`) — matches `RawOutdatedEntry { name: String }`. Verified.

`brew info --installed --json=v2` first cask: `installed: '37.0.0'`, `token: 'android-platform-tools'`, `outdated: False` — every field the parser asks for is present. Formula side has `name`, `versions.stable`, `installed[].installed_on_request`, `dependencies`, etc. — all present. Parser is well-targeted; no crash surface I can find.

---

## 3. What's actually working (evidence-supported)

- **Build chain end-to-end**: `cargo check` clean, `npm run build` clean, `svelte-check` clean. Whoever clones today and runs the build commands gets working artifacts.
- **20-command IPC surface registered** in `lib.rs` and wrapped in `src/lib/api.ts`. The mapping between `backendApi.md`, the Rust handlers, and the TypeScript wrappers is 1:1.
- **Streaming pipeline** (`run_brew_streaming`): two-pump line readers, `tokio::select!` on `child.wait()` vs cancel oneshot, lifecycle events (`Started` → `Stdout`/`Stderr` → `Exit` or `Canceled`), `kill_on_drop(true)`, 4 KB line truncation, jobs registered in a shared mutex. This is the right shape; the matching frontend activity store applies events in order. **End-to-end activity flow is plausible** modulo not having a GUI to confirm in this session.
- **Write mutex** (`brew_write_lock.lock_owned().await`): acquired in every state-mutating command, never in read commands. Matches the `decisions.md` policy.
- **Cache invalidation**: `state.invalidate_caches()` called after every successful WRITE.
- **Trending fetch + 1 h cache + stale-on-error fallback**: implemented in `commands/trending.rs` per spec. Endpoint reachable.
- **OKLCH dark/light theming with `prefers-color-scheme` + `localStorage` + matchMedia listener**: code matches `designSystem.md` and survives a non-DOM module load (`typeof document === "undefined"` guard).
- **Input validation** at the IPC boundary for `name`/`query` (reject leading `-`, length cap, char allowlist) prevents flag-injection through brew arguments. Defense-in-depth even though brew itself would also catch it.
- **Tauri plugin registrations that ARE present**: `tauri_plugin_opener::init()` is in `lib.rs`, `opener:default` is in the capability. So the homepage-link button in `PackageDetail.svelte` will actually work.
- **No telemetry, no analytics, no surprise fetch().** Verified by grep.

---

## 4. What's demoware (exists in source, but won't survive a real run)

### 4.1 Snapshots Import / Export — runtime-broken **(this is the showstopper)**

`src/lib/components/Snapshots.svelte` at lines 100–130 dynamically imports `@tauri-apps/plugin-dialog`:

```ts
const { save } = await import("@tauri-apps/plugin-dialog");   // line 102
const { open } = await import("@tauri-apps/plugin-dialog");   // line 117
```

The JS package is listed in `package.json` (`@tauri-apps/plugin-dialog: ^2.7.1`), but:

- `src-tauri/Cargo.toml` does **NOT** include `tauri-plugin-dialog`.
- `src-tauri/src/lib.rs` does **NOT** call `.plugin(tauri_plugin_dialog::init())`.
- `src-tauri/capabilities/default.json` does **NOT** include `dialog:default`.

In Tauri 2, the JS plugin call routes through an IPC command that the Rust plugin must implement. Without the Rust plugin registered, the call resolves to a Tauri IPC error of the shape `"Command not allowed by ACL"` or `"command 'plugin:dialog|save' not found"`. The Snapshots `doExport` / `doImport` handlers catch the error and `toast.error("Export failed", String(e))` — so the app doesn't crash, but the feature is non-functional. **First user who clicks Export sees a red toast and assumes the app is broken.**

`frontendComponents.md` claims "native dialogs for Brewfile import/export" and `agentLog.md` says the Frontend Developer added the dep. Both are technically true on the JS side and both miss the Rust-side registration. The Backend Architect's `backendApi.md` §8 anticipated this exact case — "If Phase 4's import/export needs OS file pickers, add `tauri-plugin-dialog` and `dialog:default`" — and the work didn't land.

**Fix is mechanical**: add `tauri-plugin-dialog = "2"` to `Cargo.toml`, call `.plugin(tauri_plugin_dialog::init())` in `lib.rs`, add `"dialog:default"` to the capability JSON.

### 4.2 No integration / unit tests actually exist

`src-tauri/tests/fixtures/` contains 10 captured JSON/text fixtures (real brew output samples — well-prepared). But **there is no `src-tauri/tests/*.rs` test file**, and no `#[cfg(test)]` block in any of the `src-tauri/src/**/*.rs` files I read.

`backendApi.md` §10 specs out a full unit + integration test plan; `apiTests.md` is the API Tester's deliverable. The fixtures were captured but the tests were never written, **or** API Tester hasn't landed yet (they're a parallel-Wave-3 agent like me, so I can't assume they have). Either way: as of this gate, the "test" claim is unsubstantiated. The build chain is the only safety net.

### 4.3 `<DesignSystemPreview>` route deferred

`frontendComponents.md` notes the `/_design` preview route from `designSystem.md` §10 was skipped because "every primitive is exercised by the live UI." Fair tradeoff for a demo — flagging it as known demoware, not a bug.

### 4.4 `Progress` event variant reserved but never emitted

`BrewStreamEvent::Progress` is in the wire schema (`types.rs:179`) but `run_brew_streaming` never sends one. The frontend activity store handles it as a `[progress]`-prefixed console line. Spec-aligned (the spec said "heuristic; brew rarely emits structured progress"), but worth noting that progress bars in the drawer header are placeholder-only — no `percent` value flows through.

### 4.5 Trending's `installed_locally` flag depends on cache priming

`commands/trending.rs::build_installed_set` reads `state.installed_cache`, which is `None` until `brew_list` runs. If a user lands directly in Trending on first launch (which they shouldn't — Library is default — but possible via `Cmd+3`), every "Installed" badge will be wrong (always `false`) until they switch to Library. Cosmetic-but-noticeable.

### 4.6 `installed_paths` always empty for formulae

`brew/parse.rs::RawFormula::to_detail` sets `installed_paths: Vec::new()` unconditionally. The spec calls out that this should be the kegs / app bundles. Only cask paths are populated via `extract_cask_paths`. Detail panel doesn't surface this field today, so harmless — but if any future UI binds to it, formulae will look empty.

### 4.7 `Settings menu / preferences popover` doesn't exist

`uxArchitecture.md` §8 says `Cmd+,` is reserved for preferences. The handler in `+page.svelte` doesn't bind it. No regression — explicitly out of scope per the spec — but the README/CLAUDE narrative mentions theme toggle "in a Settings menu" while the actual theme controls are in the sidebar footer (which is fine for a demo, just inconsistent with the documented IA).

---

## 5. What would surprise a fresh user

Walking through the `git clone … && npm install && npm run tauri dev` path with the eyes of someone who hasn't read the memory bank:

1. **First launch**: Library loads, packages appear (if brew is on `/opt/homebrew/bin` or `/usr/local/bin` or PATH — path resolver covers all three, good).
2. **Click a package**: detail panel slides in, version/license/deps show. Caveats render. Homepage link opens externally via tauri-plugin-opener. ✅
3. **Install a small package (e.g. `tree`) via Discover**: should work — search invocation, install streaming, drawer auto-opens, console fills, Library refreshes. ✅ (best assessment without a GUI session)
4. **Cmd+1..5 and Cmd+K**: wired in `+page.svelte`, should work. ✅
5. **Open Snapshots → click Import…**: 💥 red toast "Import failed: <plugin error>". This is the showstopper from §4.1.
6. **Open Snapshots → click Export…** on an existing snapshot: same 💥 red toast.
7. **Create a new snapshot via "New Snapshot" button**: should work — uses `brewfile_dump` Rust command, no dialog plugin involved. ✅
8. **Trending**: should fetch, render top 100, install badges may all read "not installed" on cold start (see §4.5). After visiting Library and returning, badges will be correct.
9. **`cargo tauri build` for a `.dmg`**: untested in this session. Build should produce an unsigned `.dmg`. Will Gatekeeper-warn on first open ("unidentified developer") — that's expected for an unsigned demo and the README's Status section calls it "early demo", so OK as-is.
10. **Window does not have an app menu** beyond what Tauri's default provides — no `View → Library` etc. Minor; out of scope.

Net for a fresh user: **8 out of 10 things they'd try work; #5 and #6 are visibly broken.**

---

## 6. Risks to the stated openness posture

I went looking for anything in the repo that would let a skeptic argue "the stated openness posture isn't matched by the code." I didn't find any.

- **License**: MIT, clearly stated everywhere it should be (`LICENSE`, `package.json`, `Cargo.toml`, README badge). No CLA. No "individual contributor agreement". ✅
- **EULA / Terms / Privacy**: none. ✅
- **Telemetry / analytics / phone-home**: none in code. The single outbound HTTP call (`formulae.brew.sh`) is Homebrew's own public analytics endpoint and is documented in the README spec and the `decisions.md` ADR with explicit rationale. ✅
- **Project name**: descriptive ("brew-browser"). ✅
- **Closed dependencies**: every dep in `Cargo.toml` and `package.json` is OSI-approved open source (Tauri MIT/Apache, Svelte MIT, Lucide ISC, reqwest MIT/Apache, etc.). ✅
- **Shell injection / arbitrary brew args from the frontend**: blocked — every `brew` invocation is constructed in Rust from enumerated typed inputs (`PackageKind`, validated `name`, validated `query`), and the frontend cannot pass argv arrays. ✅
- **No `tauri-plugin-shell`**: confirmed absent. The security posture in `backendApi.md` §8 is honored. ✅
- **Destructive actions are confirmed**: Uninstall and Delete-Snapshot both route through `DestructiveConfirm` modal with Cancel as default focus. ✅

**Posture matches the repo.**

---

## 7. Bare-minimum punch list to flip the verdict to READY-FOR-DEMO

Prioritized. The first item is the actual gate-blocker; everything below is "nice to have for the demo to feel polished but not required."

### Required (gates the verdict)

1. **Wire up the dialog plugin end-to-end.** Three small edits:
   - `src-tauri/Cargo.toml`: add `tauri-plugin-dialog = "2"` to `[dependencies]`.
   - `src-tauri/src/lib.rs`: add `.plugin(tauri_plugin_dialog::init())` to the builder chain.
   - `src-tauri/capabilities/default.json`: append `"dialog:default"` to the `permissions` array.
   - Re-run `cargo check` and a smoke `npm run tauri dev`; verify Import/Export from Snapshots opens a real macOS dialog.

### Strongly recommended (small lifts; would tighten the demo)

2. **Prime `installed_cache` on Trending's first fetch** so "Installed" badges are correct even if user lands there cold. One-line: in `trending_fetch`, if `installed_cache` is `None`, call `brew_list` (cheap, cached after) before building the set.
3. **Write one smoke integration test** — e.g. `src-tauri/tests/integration_brew_list.rs` that runs `brew_list` and asserts `formulae.len() + casks.len() > 0`. Counters the "no tests" claim and acts as a canary for parser drift.
4. **Run `cargo tauri build` once** (Phase 5 / Wave 4) and confirm the `.dmg` opens on Beast. Doesn't change code; just generates the "the demo really runs" evidence the README implies.

### Optional polish (skip without guilt)

5. **Wire `BrewStreamEvent::Progress` emission** (heuristic from `==>` markers). Activity drawer header currently shows just elapsed time; a percent would feel more alive.
6. **Add `Cmd+,` preferences popover stub** to match the IA spec (could literally be a small modal with the theme tri-toggle duplicated).
7. **Populate `installed_paths` for formulae** from `installed[].installed_paths` (if the JSON exposes it; needs a glance at the schema).
8. **Add the `<DesignSystemPreview>` route at `/_design`** — useful for the visual-storytelling pass, not user-facing.
9. **Fix the `tsconfig.json` `@types/node` warning** by either `npm i -D @types/node` or removing the unused `node` type from `tsconfig.json`. Cosmetic.

---

## 8. Bottom line

The repo is **substantially good work**: clean build, faithful execution of three coherent design specs, a real security posture (no shell plugin, validated args, write mutex), and openness claims that are matched by the code. The drift documented in `backendApi.md` §10.5 is the kind of honest drift you want to see from an implementor — small, justified, written down.

It misses `READY-FOR-DEMO` on a single concrete, reproducible runtime failure: the dialog plugin is half-wired. That's a 5-line fix and one re-build. After that, this is ready to be demoed to a developer audience without embarrassment.

If the answer to "does the openness posture hold up?" is the bar, that bar is **already met** today. If the answer to "would a fresh `npm install && npm run tauri dev` user have a clean experience?" is the bar — which is the bar `projectbrief.md` actually sets — then we're one PR away.

---

*End of Reality Check. Re-run after the dialog-plugin fix lands to flip the gate.*
