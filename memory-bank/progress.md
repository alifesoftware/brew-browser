# Progress

## 2026-05-24 (overnight)

### Done since last sync

- ✅ `git init` + first commit (`653e26f`) — initial release, 186 files
- ✅ `gh repo create msitarzewski/brew-browser --public --push` — repo live on GitHub
- ✅ Bulk categorize run completed against Claude Haiku 4.5 — 15,974 items, $1.50, 19 min
- ✅ Second commit (`c72e31d`) — categories.json (838 KB) + landing page in-repo
- ✅ Third commit (`2dad9be`) — Caddyfile snippet removed (user handles Caddy config manually)
- ✅ Landing page rsync'd to `michael@100.98.187.7:Sites/brew-browser/` on umbp
- ✅ Full SEO/social treatment added to landing: OG, Twitter/X cards, JSON-LD SoftwareApplication, PWA manifest, robots.txt, sitemap.xml, 1200×630 social card
- ✅ Social card iterated through multiple designs based on user feedback
- ✅ `ideas.md` captures: Recipes, optional GitHub OAuth, Liquid Glass / NSVisualEffectView discussion, Discover-UI surface ideas

### Phases

| Phase | Status |
|-------|--------|
| 0 — Scaffold | ✅ |
| 1 — Read-only Homebrew browser | ✅ |
| 2 — Search Homebrew index | ✅ (categories UI pending) |
| 3 — Install/uninstall/upgrade w/ streaming | ✅ |
| 4 — Brewfile snapshot/restore | ✅ (NB: known upstream brew bundle bug surfaced via friendly error mapping) |
| 5 — Polish + build artifact | ✅ (unsigned .dmg; signing pending cert install) |
| 6 — Trending tab | ✅ |
| 7 — Cask icons installed | ✅ |
| 8 — Cask icons homepage cascade | ✅ |
| Security — audit + fixes + tool battery + re-audit | ✅ READY-FOR-SCRUTINY |
| Reframe pass | ✅ counter-narrative dropped from all docs |
| Categorize tool + bulk run | ✅ 15,974 items via Claude Haiku 4.5 |
| Landing page + SEO/social | ✅ deployed to umbp |
| **v0.1.0 GitHub release** | ✅ SHIPPED — signed/notarized .dmg attached at <https://github.com/msitarzewski/brew-browser/releases/tag/v0.1.0> |
| **Phase 9a — Discover category tile UI** | ✅ tile grid + filtered view + Lucide icons, uncommitted |
| **Phase 9b — Category linking pass** | ✅ multi-select chip filter (Discover + Library), category pills on PackageDetail, sortable columns (Library + Trending), fixed dangling `installed` pill, uncommitted |
| **Phase 11 — Dashboard** | ✅ hero/updates/composition/donut/storage cards; brand → home; updates card → outdated library; uncommitted |
| **Phase 11b — Services** | ✅ sidebar item ⌘5, page with start/stop/restart, per-package detail card, sidebar badge for running count, uncommitted |
| **Phase 11c — Native macOS feel** | ✅ vibrancy + drag regions (data-tauri-drag-region + capability), traffic-light-aware sidebar, uncommitted |
| **Phase 11d — Activity persistence** | ✅ localStorage mirror, cap 50 jobs / 500 lines, hydrate on bootstrap, uncommitted |
| **Phase 12a — Bundled catalog + manual refresh** | ✅ |
| **Phase 12b — Settings shell** | ✅ |
| **Phase 12c — GitHub anonymous tier** | ✅ (combined with 12e in one Backend Architect pass) |
| **Phase 12d — Settings: network + paranoid + settings persistence** | ✅ |
| **Phase 12e — GitHub Device Flow OAuth + Keychain** | ✅ (combined with 12c) |
| **Phase 12f — GitHub authed actions** | next (after Wave 1+2 commit) |
| **Phase 13 — Catalog enrichment (Haiku)** | queued, parallel-OK with 12f |
| **Phase 14 — bundled cask icons** | DROPPED (trademark/redistribution risk) |
| **Phase 9c — "Wrong?" GitHub-issue link** | folds into 12f |
| **Phase 9d — `installedAt` on Package + Last-Updated sort** | small standalone, not in any phase |
| **Phase 10 — Recipes** | deferred — catalog now available so unblocked |

### Phase 9b notes

- New store: `src/lib/stores/discover.svelte.ts` — multi-select `selectedCategories: Set<string>`, shared by Discover + Library + PackageDetail. `selectOnly(slug)` for tile-click semantics, `toggle(slug)` for chip add/remove.
- Discover.svelte: replaces local single-`activeCategory` with the shared store; tile click → adds single chip; chip bar above results with per-chip X + Clear button; search results filter to OR-match selected chips; chip-only browse mode (no query, chips set) lists union sorted alphabetically.
- Fixed UX bug from the user's screenshot: `installed` pill no longer floats. Two row layouts: `.row--with-desc` (1fr 80px 2fr auto) for search; `.row--no-desc` (1fr 80px auto) for chip-filtered browse.
- PackageDetail: new "Categories" meta row with clickable pills. Click jumps to Discover with that single category selected (closes detail panel so user lands on the filtered list, not an obscured view).
- New component: `src/lib/components/SortableHeader.svelte` — small reusable header button with up/down arrow indicator, click toggles direction or switches column. Uses `aria-label` (not `aria-sort`, since that requires `role="columnheader"` and our list-grids aren't true tables).
- Library: sortable Name / Version / Type / Outdated; shares the Discover category chips so the user can keep context across tabs; updated empty-state messaging to reflect chip vs. text filters separately.
- Trending: sortable # / Name / Type / Installs. Installs defaults to descending on first click.
- Lint/test: `npm run check` 0 errors / 1 pre-existing warning. `npm run build` clean in 1.64s. Backend untouched this pass — no Rust regression risk.
- Status: code is in working tree, NOT committed. Awaiting user UX confirmation.

### Phase 11 notes (Dashboard + Services + native feel + persistence)

Single big session 2026-05-24-night. Highlights:

- **Dashboard.svelte** is the new default landing. Hero row (installed / outdated / brew version), Updates panel with one-click upgrade-all (and the title is a clickable link → Library outdated filter), Composition split bar with on-request/dep/pinned meta, Top-Categories donut (180px SVG, 9-color palette, top 8 + Other, click legend → Discover with chip pre-selected), Storage card with 4 paths and Open-in-Finder per row.
- **Donut math:** `stroke-dasharray="(pct/100)*C C"` + `stroke-dashoffset="-(startPct/100)*C"` + `rotate(-90)` for top start. Center text shows total installed.
- **Services backend** (`commands/services.rs`): 5 commands (list, clear-cache, start, stop, restart), 5s list cache, write-lock around state mutations, alphanumeric+symbol name validation.
- **Services frontend:** sidebar item ⌘5, sortable Name/Status/User columns, per-row action buttons (smart-disabled by current state), badge = count of running services. PackageDetail shows a Service card with pill + 3 buttons when the formula has a brew services entry.
- **Disk usage backend** (`commands/disk_usage.rs`): `disk_usage` + `open_in_finder`, 4 paths surveyed in parallel via `tokio::join!`, 60s cache, security gate on Finder reveal (must be inside Homebrew prefix/cache).
- **Native macOS feel:** vibrancy via `window-vibrancy = "0.6"` + `apply_vibrancy(NSVisualEffectMaterial::HudWindow, …)`; tauri.conf.json `transparent: true` + `titleBarStyle: "Overlay"` + `hiddenTitle: true`; sidebar brand padded to clear traffic lights; `data-tauri-drag-region` on brand-wrap + every panel-head with the new `core:window:allow-start-dragging` capability.
- **Activity persistence:** localStorage mirror `brew-browser:activity:v1`, cap 50 jobs / 500 lines per job, debounced 400ms writes + immediate flush on terminal events, hydrate from +layout mount.
- **Sortable lists hardening:** `1fr` → `minmax(0, 1fr)` everywhere a flex column had text (Discover, Library header + PackageRow, Trending). Fixed cross-row pill alignment that depended on name length. Also `auto` → `90px` for the installed column so it doesn't collapse-and-shift the kind cell.
- **Trending Refresh fix:** the force flag now busts the backend cache before calling `trending_fetch` — was silently ignored before.
- **Dashboard scroll + drag bug fix:** removed the fixed-position drag-overlay (was eating scroll wheel + not actually triggering drag); fixed flex children getting shrunken to fit by adding `.body > * { flex-shrink: 0 }`.
- **Test count:** 207 → 210 (3 new for `services` name validation, 2 for `disk_usage` du_bytes, 1 for `categories` already counted last session = pre-session 204 + 6 = 210).

### Phase 9a notes

- Backend: `commands/categories.rs` — `categories_data` Tauri command, embeds JSON via `include_str!` (zero runtime file dep), parsed once + memoised on `AppState.categories_cache`. 1 new unit test (205 total, was 204).
- Frontend types: `CategoryMeta`, `CategoriesData` in `types.ts`.
- API wrapper: `categoriesData()` in `api.ts`.
- Store: `src/lib/stores/categories.svelte.ts` — lazy-load, derived `tiles` (sorted by count, uncategorized last), `tokensInCategory(slug)` for the filtered view, `categoriesOf(name, kind)` for future chip rendering.
- Icon resolver: `src/lib/util/categoryIcon.ts` — static map of 19 Lucide icons, falls back to `HelpCircle`.
- Discover.svelte: new tile grid (`auto-fill, minmax(180px, 1fr)`), clicking a tile drills into a filtered list, back button returns to grid. Search still wins when there's a query.
- Lint/test: cargo clippy `-D warnings` clean, cargo test 205 pass, `npm run check` 0 errors, `npm run build` clean.
- Status: code is in working tree, NOT committed. Awaiting user sign-off on UX before commit.

### Test + build status (current)

- `cargo test --manifest-path src-tauri/Cargo.toml`: **210 passed / 0 failed / 6 ignored** (up from 204)
- `cargo check`: clean
- `cargo clippy --all-targets -- -D warnings`: clean
- `npm run build`: clean
- `npm run check`: 0 errors (1 pre-existing tsconfig-node warning)
- `cargo deny check`: advisories ok, bans ok, licenses ok, sources ok (pre-session)
- `cargo tauri build`: produces signed/notarized 5.7 MB `.dmg` (v0.1.0 already shipped)

### Security posture

| Tool | Result |
|------|--------|
| Wave 1 audit findings | **16/16 verified fixed** (0C / 0H / 0M / 0L / 0N open) |
| `cargo audit` | 0 vulns |
| `cargo deny check` | advisories+bans+licenses+sources ok |
| `npm audit --omit=dev` | 0 vulns |
| `osv-scanner` | 19 advisories (all Linux-only or acknowledged) |
| `gitleaks` | 0 leaks in source |
| `semgrep` (security-audit + OWASP-10 + rust + typescript) | 0 findings |
| `unsafe` Rust in brew-browser | 0 |
| `@html` / `innerHTML` / `eval` in frontend | 0 |
| Tauri shell plugin | not used (IPC is the security boundary) |

### Open items

| Item | Blocker |
|------|---------|
| Apple Developer ID Application cert | User must install via developer.apple.com |
| Signed + notarized `.dmg` | Above |
| v0.1.0 GitHub release with `.dmg` attached | Above |
| Updated social card PNG saved to persistent path | User must drop file somewhere I can grab |
| Master icon swap to beer-mug variant (optional) | Decision pending |
| Phase 9 — Discover category UI build | Ready to start when user signals |

### Repo state

```
/Users/michael/Clean/brew-browser/  (15.9k+ packages categorized, 2 production commits + this sync pending)
├── LICENSE                           MIT
├── README.md                         polished, security section, 4-path network disclosure
├── CONTRIBUTING.md                   141 lines
├── SECURITY.md                       responsible disclosure
├── PLAN.md                           phase tracker
├── .gitignore                        comprehensive (target/, node_modules/, .env, etc.)
├── package.json                      brew-browser, MIT
├── src/                              36+ files
├── src-tauri/
│   ├── src/                          22 Rust files (modular)
│   ├── Cargo.toml                    8 deps
│   ├── deny.toml                     permissive-license allowlist
│   ├── data/categories.json          838 KB — 7,607 casks + 8,367 formulae from Haiku 4.5
│   ├── icons/                        38 minted platform icons
│   ├── tests/                        integration + 10 real-brew fixtures
│   └── target/release/bundle/dmg/    brew-browser_0.1.0_aarch64.dmg (6.1 MB, unsigned)
├── tools/categorize/                 offline LLM-driven category tool
│   ├── categorize.py                 main script
│   ├── prompts/system.txt            calibration prompt
│   ├── .env.example                  template (real .env gitignored)
│   ├── state/last-tokens.json        diff state (15,974 tokens recorded)
│   └── README.md                     setup + cron docs
├── landing/                          static landing page
│   ├── index.html                    full OG/Twitter/JSON-LD/PWA treatment
│   ├── style.css                     OKLCH tokens, dark-first
│   ├── brew-browser.svg              icon copy
│   ├── manifest.json                 PWA
│   ├── robots.txt + sitemap.xml      SEO basics
│   ├── social-card.png / .svg        1200×630
│   └── README.md                     deploy via rsync to umbp
├── docs/icon/                        master SVG + size previews
└── memory-bank/                      20 files (this dir)
```

## 2026-05-24 (late session — Phase 12 Wave 1 + Wave 2)

### Done

- ✅ Commit `84ad010` pushed (Phase 9 + 11 + memory bank refresh)
- ✅ Phase 12 plan written: `memory-bank/phase12-plan.md`
- ✅ Pre-implementation Security Engineer review: `memory-bank/scans/phase12-security-review.md` — APPROVED with explicit gates
- ✅ **Phase 12a** (Backend Architect agent) — bundled catalog + manual refresh, +38 tests
- ✅ **Phase 12b** (Frontend Developer agent) — Settings shell + 6 sections + brew analytics, +8 tests
- ✅ **Phase 12d** (Backend Architect agent) — paranoid mode + settings persistence + Network section, +18 tests
- ✅ **Phase 12c + 12e** combined (Backend Architect agent) — GitHub anonymous tier + Device Flow + Keychain, +60 tests
- ✅ Phase 13 plan written: `memory-bank/phase13-plan.md` — Tier A friendly names+summaries, Tier B use cases+similar+tags, AI Features master toggle, ~$20 cost, zero runtime LLM calls
- ✅ Phase 14 (bundled cask icons) **explicitly DROPPED** — trademark/redistribution risk, runtime probe + paranoid gate is enough

### Phases (updated)

| Phase | Status |
|-------|--------|
| **Phase 12a — Bundled catalog + manual refresh** | ✅ |
| **Phase 12b — Settings shell + brew analytics** | ✅ |
| **Phase 12c — GitHub anonymous repo stats** | ✅ (combined with 12e) |
| **Phase 12d — Paranoid + network settings + settings persistence** | ✅ |
| **Phase 12e — Device Flow OAuth + Keychain** | ✅ (combined with 12c) |
| **Phase 12f — GitHub authed actions** | next |
| **Phase 13 — Catalog enrichment** | queued, can run parallel with 12f |
| **Phase 14 — bundled cask icons** | DROPPED (trademark risk) |
| **Phase 10 — Recipes** | deferred — depends on catalog (now available) |
| **Phase 9d — installedAt + Last-Updated sort** | small standalone, not blocking |

### Test + lint status (current)

- `cargo test`: **334 passed / 0 failed / 6 ignored** (was 274 at start of Wave 2; 210 at start of session)
- `cargo clippy --all-targets -- -D warnings`: clean
- `npm run check`: 0 errors, 1 pre-existing tsconfig-node warning
- `npm run build`: clean

### Phase 12 Wave 2 notes

**Wave 2 ordering (Option A — Foundation-first):** 12d → combined 12c+12e → 12f. Locked in by user. Reasoning: 12d delivers `require_network` helper + settings persistence; 12c+12e then consume the helper directly (no TODOs); combined as one Backend Architect pass because 12c and 12e both touch the same `src-tauri/src/github/` module.

**Phase 12a key deviations from spec (accepted):**
- `CatalogRefreshInProgress` returned as generic `InvalidArgument` until 12d added the proper variant — agent left a TODO grep-marker
- Bundled gzipped catalog is 6.1 MiB not "~3 MiB" estimate (catalog grew upstream)
- `fetch.py` doesn't strip unused JSON fields (deferred — would shrink to ~1 MiB at cost of build-time coupling to Rust struct shape)

**Phase 12b key deviations (accepted):**
- `commands/mod.rs` alphabetical position is true-alphabetical (brew_env < brewfile), not literal-spec position
- Lucide has no `github` icon (trademark) → `git-fork` substituted for the GitHub section
- Settings modal sized `220px nav + 1fr content` not `350px + 600px` (looked awkward at macOS density)
- `brew_get_analytics` parser accepts both trailing-period and non-period forms (empirically brew has shipped both)
- Activity caps wired to Settings but not yet consumed by activity store (deferred — value persists, no retroactive trim)

**Phase 12d key deviations (accepted, more conservative than spec):**
- Unknown enum variant → file treated as Corrupt → fail closed (instead of "log + substitute default"). Aligned with §12d "fail closed when corrupt" rule
- `require_network` gates Trending even on cache hits (UX consistency over micro-savings)
- Catalog stale banner threshold + cask icon mode NOT retroactively wired to consume the new settings — store is ready, consumers swap as a 1-line change later

**Phase 12c+12e key deviations (accepted):**
- Cache TTL backdating test rewritten as constant-pin + fresh-read positive test (filetime isn't a dep)
- CSP comment moved to Rust module docs (tauri-build rejects unknown JSON fields like `_comment_csp`)
- Custom `KeychainSlot` trait + in-memory mock instead of `keyring` crate's mock feature (same coverage, no runtime context switch)
- Username resolution failure is non-fatal during sign-in (token still stored; username shows "github user" until next sign-in)
- `AuthRequired` + `ScopeRequired` error variants land but `#[allow(dead_code)]` until 12f consumes them

### Files staged (47 changes, ready to commit)

Backend: `Cargo.toml`, `Cargo.lock`, `tauri.conf.json`, `capabilities/default.json`, `src/{catalog,github,util}/`, `src/commands/{catalog,brew_env,disk_usage,github,services,settings}.rs`, `src/commands/{mod,trending,cask_icon_homepage}.rs` (paranoid gate wiring), `src/{error,lib,state}.rs`

Frontend: `src/{app.css, +layout, +page}.svelte`, `src/lib/{api,types}.ts`, `src/lib/components/{Dashboard, Discover, Library, PackageDetail, PackageRow, Services, Settings, SettingsSection*, DeviceFlowModal, Sidebar, Snapshots, Trending, ActivityHistory, SortableHeader}.svelte`, `src/lib/stores/{activity, categories, discover, github, library, services, settings, trending, ui}.svelte.ts`, `src/lib/util/categoryIcon.ts`

Docs: README.md (Open by default → 7 paths + Paranoid Mode), BUILD.md (GitHub OAuth section), memory bank updates

Data: `src-tauri/data/catalog/{formula,cask}.json.gz` + `manifest.json`

Tools: `tools/catalog/{fetch.py,README.md}`

Misc untracked: `PHILOSOPHY.md` (user-authored, 271 lines)

## 2026-05-24 (evening — Phase 12+13 wrap)

### Done

- ✅ Commit `99a1f2c` pushed — Phase 12 Wave 1+2 (catalog 12a, settings 12b, paranoid 12d, GitHub anonymous + Device Flow 12c+12e). 47 files. Test count 210 → 334.
- ✅ Commit `8b89c40` pushed — Phase 12f (GitHub authed actions: star/unstar/is_starred/watch/unwatch/create_issue + Wrong? link + Dashboard personal-stats card) **plus** Phase 13 infrastructure (enrichment module + commands + store + Settings AI Features master toggle + placeholder bundle + `tools/enrich/enrich.py`). ~30 files. Test count 334 → 385.
- ✅ Search-no-match hotfix in `src-tauri/src/commands/search.rs` — `brew search --formula <q>` and `--cask <q>` each exit 1 with "Error: No formulae or casks found for..." when their own kind has zero matches; for formula-only tokens like `abcl` the cask side legitimately has nothing. Each side now handled independently; "no match" treated as empty, only real errors propagated. +3 unit tests. **Uncommitted** in working tree — narrow scope, awaiting user.
- ✅ Tier A catalog enrichment kicked off via `python tools/enrich/enrich.py --tier-a` — running in background as of 2026-05-24 evening. Will produce ~500 KB gzipped `enrichment.json.gz` with friendly-name + summary for the ~5,000 packages with thin or missing `desc`. Estimated cost $3-5 against Haiku 4.5. Hands off `src-tauri/data/enrichment.json.gz` until the run completes.

### Phases (updated)

| Phase | Status |
|-------|--------|
| **Phase 12a — Bundled catalog + manual refresh** | ✅ shipped (`99a1f2c`) |
| **Phase 12b — Settings shell + brew analytics** | ✅ shipped (`99a1f2c`) |
| **Phase 12c — GitHub anonymous repo stats** | ✅ shipped (`99a1f2c`, combined with 12e) |
| **Phase 12d — Paranoid + network settings + settings persistence** | ✅ shipped (`99a1f2c`) |
| **Phase 12e — Device Flow OAuth + Keychain** | ✅ shipped (`99a1f2c`, combined with 12c) |
| **Phase 12f — GitHub authed actions** | ✅ shipped (`8b89c40`) |
| **Phase 13 — Catalog enrichment infrastructure** | ✅ shipped (`8b89c40`); Tier A bundle baking in background |
| **Phase 9c — "Wrong?" GitHub-issue link** | ✅ shipped (folded into 12f in `8b89c40`) |
| **Phase 14 — bundled cask icons** | DROPPED (trademark risk) |
| **Phase 10 — Recipes** | deferred — catalog + enrichment now available, naturally pairs |
| **Phase 9d — installedAt + Last-Updated sort** | small standalone, not blocking |
| **Tier B Tahoe Liquid Glass (Swift bridge)** | v0.2 |

### Files touched

3 commits across the session totalled **~110 files** modified or added (84ad010 Phase 9+11 was 38 files; 99a1f2c Phase 12 Wave 1+2 was 47 files; 8b89c40 Phase 12f + Phase 13 was ~30 files; some overlap on `lib.rs` / `commands/mod.rs` / shared state). 70+ unique files when deduplicated.

### Test + lint status (current)

- `cargo test`: **385 passed / 0 failed / 6 ignored** (was 334 at start of evening; 210 at start of session)
- `cargo clippy --all-targets -- -D warnings`: clean
- `cargo check`: clean
- `npm run check`: 0 errors, 1 pre-existing tsconfig-node warning
- `npm run build`: clean

### Phase 12f notes

- `authed_gate(state, homepage, feature)` chain — single helper, 5 ordered steps: `require_network` → `parse_github_url` → `read_token` → `read_scopes` → `actions::build_client`. Every action command routes through it. Paranoid fires FIRST so we don't leak "auth required" semantics to a user who told us to stop making outbound calls.
- Issue creation input rules implemented as separate sanitisers in `actions::sanitise_title` / `sanitise_body` / `sanitise_labels`. Title strips control chars except `\t`. Body strips null bytes only (GitHub renders Markdown — don't maul user-intended markup). Labels are `≤ 10` entries matching `^[A-Za-z0-9_./-]+$`.
- Dashboard "Personal stats" card uses a 50-permit `Semaphore` for the batch `github_is_starred` calls (one per installed package whose homepage is a GitHub URL). Backend cache is 24h so repeat opens are free.
- "Wrong?" categorization deeplink uses `percent_encoding::utf8_percent_encode` rather than format-string concatenation for the prefilled body.
- `BrewError::AuthRequired` and `BrewError::ScopeRequired { scope }` (added in 12e behind `#[allow(dead_code)]`) are now consumed — `dead_code` allowance removed.

### Phase 13 notes

- `tools/enrich/enrich.py` accepts `--tier-a`, `--tier-b`, `--all`, `--dry-run`. Running with no flags prints help and exits — **you cannot accidentally spend money on an Anthropic API call**.
- Placeholder bundle ships at 114 bytes (empty entries map) so the build is reproducible without an API key. Real Tier A bundle is ~500 KB gzipped; Tier A + B together ~2 MiB gzipped. Bundle grows the binary from 6 MiB (catalog) to ~8.5 MiB.
- Rust loader applies the same defense-in-depth caps as the Phase 12a catalog even though the bundle is built by us: 32 MiB raw cap, 64 MiB decompressed cap, per-field length caps (`friendly_name ≤ 100`, `summary ≤ 1024`, `use_cases ≤ 5 entries of ≤ 200 chars`, `similar ≤ 50 tokens` each re-validated against `validate_package_name`, `tags ≤ 12 entries of ≤ 30 chars`).
- **Zero runtime LLM calls.** The `anthropic` SDK is a Python build-time dep only; it never enters the Rust binary. The AI Features toggle controls *rendering*, not *fetching*.
- BUILD.md added an "Catalog enrichment (Phase 13 — optional)" section covering the run-order, tier flags + costs, `ANTHROPIC_API_KEY` location, and an operational examples block.

### Search no-match hotfix notes

- **Bug existed since Phase 2** — surfaced by user search behavior this session (likely a formula-only token like `abcl`).
- Root cause: `f_res.map_err(...)??` flattened both the join error and the inner `BrewError`, so a `BrewExitNonZero { exit_code: 1, stderr_excerpt: "Error: No formulae or casks found..." }` from the cask side propagated as a typed error instead of an empty result.
- Fix: split the flattening, pattern-match on the inner result, and treat the "no match" error pattern as `String::new()`. If BOTH sides fail in unrelated ways, surface the formula error (matches the order the user is most likely searching for).
- New `is_brew_search_no_match` helper + 3 unit tests (`detects_no_match_exit_pattern`, `does_not_match_other_brew_errors`, `does_not_match_non_exit_errors`).
- Test count net change: 0 (the existing search tests still pass; the new tests are additive). 385 → 385.

### Documentation pass (this section)

The Technical Writer pass appended sections to:
- `memory-bank/security.md` §13 ("Phase 12 + 13 additions") — 7 sub-sections covering the new attack surface, gates, and verification approach for each sub-phase. Wave 3 READY-FOR-SCRUTINY verdict above is untouched.
- `memory-bank/backendApi.md` §13 — every new Tauri command shipped this session with signature, paranoid-mode-gate status, auth requirements, and source file path.
- `memory-bank/frontendComponents.md` — new "Phase 9+11+12+13 additions" section with components, stores, utilities, and mount points.
- `memory-bank/activeContext.md` — "Post-Phase-12+13 sync" section.
- `memory-bank/progress.md` (this file) — "Phase 12+13 wrap" section.
- Spot-fixes to README.md (Status line, Architecture line — ~55 commands not ~20) and BUILD.md (cross-references to the two phase plans).


## 2026-05-24 (late session — Phase 12g/13b cleanup + UI polish)

### Done since commit `8b89c40`

#### Tier A enrichment baked
- `python tools/enrich/enrich.py --tier-a` — full run against Anthropic Haiku 4.5
- **15,725 entries** written to `src-tauri/data/enrichment.json.gz` (771 KB compressed, 0.74 MiB)
- Total bundled data: 6.1 MiB catalog + 0.74 MiB enrichment ≈ 6.9 MiB
- Cost: ~$3-5 against user's Anthropic API
- Sample quality validated on first 12 entries (a2ps, abcl, ab-av1, etc.) — Haiku correctly identifies niche tools, transforms opaque tokens to readable names, leaves already-readable tokens alone
- `tools/enrich/enrich.py` patched with cascade `.env` lookup (tools/enrich/.env → tools/categorize/.env → process env) so the user doesn't have to duplicate ANTHROPIC_API_KEY

#### Phase 12g/13b cleanup (all 4 IMPORTANT findings from Code Reviewer addressed)
1. **Phase 12a frontend wired** (was dead code from UI's perspective) — `Catalog`/`Formula`/`Cask`/`CatalogSummary` types, 6 IPC wrappers, `src/lib/stores/catalog.svelte.ts` with `summary`/`refreshing`/`isStale`/`daysOldLabel`, Dashboard catalog freshness line, Discover stale-catalog banner
2. **Three persisted settings now actually honored:** `trending_ttl_minutes` in `trending_fetch`, `cask_icon_mode` in `cask_icon_from_homepage` (with pure `cask_icon_gate_decision` helper), `catalog_auto_refresh` via new startup hook `maybe_auto_refresh_catalog` + `should_auto_refresh(schedule, age)` decision helper + extracted `refresh_catalog_inner`. +23 tests
3. **Search hotfix** — `brew search abcl` was crashing on "brew_exit_non_zero" because `brew search --cask abcl` exits 1 (formula-only token). `is_brew_search_no_match` helper now tolerates per-kind no-match exits; `brew_search_desc` verified-not-affected (exits 0 on no match). +4 tests
4. **Phase 13 friendly names in list rows** — Discover (search + chip-filtered), Library (via PackageRow), Trending all render `friendly_name` as a subtitle below the raw token when AI Features toggle is on

#### Native macOS menu
- `tauri::menu::MenuBuilder` in `src-tauri/src/lib.rs` — App menu (About brew-browser, Settings… ⌘,, Hide / Hide Others / Show All, Quit) + Edit (Undo/Redo/Cut/Copy/Paste/Select All) + Window (Minimize/Maximize/Close) submenus
- `MENU_EVENT_ABOUT` and `MENU_EVENT_SETTINGS` constants emit Tauri events; `+layout.svelte` `listen()`s and opens the matching modal
- Requires app restart (menus build at startup)

#### About brew-browser modal
- New `src/lib/components/AboutModal.svelte` — 🍺 hero, version + brew + license + repo meta, big "♥ Donate to the project" CTA, credits paragraph crediting **Agency Agents** (clickable link → https://github.com/msitarzewski/agency-agents) "powered by Anthropic's Claude Opus 4.7 and the Claude Agent SDK"
- Mounted in `+page.svelte`, opened via `ui.openAbout()` or the native App menu's "About brew-browser" item

#### GitHub Sponsors setup
- `.github/FUNDING.yml` → `github: [msitarzewski]` (surfaces "Sponsor" button on the repo page)
- Shared `src/lib/util/donate.ts` exports `SPONSOR_URL` — single source for AboutModal CTA and sidebar footer link
- Sidebar footer gets `♥ Donate` link under brew version

#### TopBar (theme + Settings group)
- New `src/lib/components/TopBar.svelte` — theme dropdown (sun/moon/monitor icon reflecting current → opens 3-item popover Light/Dark/System) + Settings gear in a subtle sunken-background button group with hair-line divider
- `position: absolute` inside `.content` (NOT fixed) — anchored to main panel area, never overlaps PackageDetail
- Theme + Settings stripped from sidebar footer
- Multiple style iterations: pill → flat → pill-with-divider → final responsive

#### Unified panel-head ("precision, happy")
- Global `.panel-head` baseline in `src/app.css` — `padding: 18px var(--space-4)`, `min-height: 60px`, `border-bottom: 1px solid var(--color-border)`, h1 `font-size: var(--text-h1); line-height: 1.2;`
- `!important` justified as cross-component coordination (Svelte scopes styles per component)
- `.content .panel-head` scopes the 96px right-padding TopBar-reserve to main panels only — detail header gets symmetric padding so close X sits flush at right edge
- Detail header gets `class="panel-head"` so it inherits the shared baseline — separator y-coordinate matches every main panel-head exactly

#### Responsive headers + columns (avoid the crashing)
- Trending / Library / Services / ActivityHistory all wrap their Refresh or "Clear completed" in `.refresh-wrap` / `.action-wrap`
- `@media (max-width: 1000px)` hides those wraps + auxiliary text ("Updated Ns ago", "N running · M total")
- Trending + Library list rows + headers get tiered responsive column drops:
  - `@media (max-width: 880px)` drops trailing 5th column (installed pill / Outdated badge)
  - `@media (max-width: 720px)` drops middle secondary column (Installs / Version)
  - `# / NAME / TYPE` always visible
- `overflow: hidden` + `min-width: 0` on every header/row cell prevents column-header glyph collision (the NAVME/INVPALLS bug)
- All hidden actions remain accessible via Cmd+R / per-row controls

#### Pillgroup unified
- Trending + Library `.pillgroup` lose the hard border, switch to sunken-background-only matching the new TopBar group pattern

#### PackageDetail rework
- h1: `enriched?.friendlyName ?? ui.selectedPackage.name` — friendly name when AI on + enrichment has one; raw token otherwise. Token always surfaces (in h1 OR in new Token meta dl row)
- Type pill right-aligned (`margin-left: auto`)
- Close X flush at right edge (after `.content`-scoped padding fix)
- AI-enriched badge removed from h1 — provenance still on summary/use_cases/similar/tags lower in body
- Detail-header separator y-coordinate matches main panel-head separator exactly (precision-happy)

#### Brew analytics parser widened
- `parse_analytics_state` now accepts `[<backend>] [a|A]nalytics are [en|dis]abled[.]` — modern brew emits `"InfluxDB analytics are enabled."` which the original strict matcher rejected
- Strict-first-line constraint preserved (no whole-output regex)
- +3 tests pinning InfluxDB + arbitrary-backend variants

#### GitHub sign-in friendlier error
- `start_device_flow` fails fast with "GitHub sign-in is not configured in this build…" when `GITHUB_OAUTH_CLIENT_ID` is still the placeholder
- `github` store uses `brewErrorMessage(e)` instead of `e.code` — human message reaches the frontend
- DeviceFlowModal drops redundant `toast.error` on error state — modal renders inline

#### Detail-panel auto-close on navigation
- `ui.setSection(s)` now also clears `ui.selectedPackage` — clicking any sidebar/Cmd+0-6 closes the detail panel

#### Other polish
- README "Open by default" updated (still 7 paths after all this)
- BUILD.md mentions GitHub OAuth App setup (still needs real client_id before release)

### Test + build status (final)

- `cargo test`: **411 passed** (was 385 at end of Phase 13)
- `cargo clippy --all-targets -- -D warnings`: clean
- `cargo check`: clean
- `npm run check`: 0 errors, 1 pre-existing tsconfig-node warning
- `npm run build`: clean

### Files this session (since `8b89c40`)

**New (5):** `.github/FUNDING.yml`, `src/lib/components/AboutModal.svelte`, `src/lib/components/TopBar.svelte`, `src/lib/stores/catalog.svelte.ts`, `src/lib/util/donate.ts`

**Backend modified (10):** `src/{app.css}` ... wait this is frontend. Backend: `src-tauri/Cargo.toml` (unchanged), `src-tauri/src/commands/{brew_env,cask_icon_homepage,catalog,search,trending,settings}.rs`, `src-tauri/src/github/auth.rs`, `src-tauri/src/lib.rs` (menu), `src-tauri/src/state.rs` (auto-refresh hook), `src-tauri/data/enrichment.json.gz` (15,725 entries)

**Frontend modified (~15):** `src/app.css`, `src/lib/api.ts`, `src/lib/types.ts`, `src/lib/components/{Dashboard,Discover,Library,PackageDetail,PackageRow,Trending,Services,Sidebar,Settings,SettingsSectionBrew,DeviceFlowModal,ActivityHistory}.svelte`, `src/lib/stores/{ui,github}.svelte.ts`, `src/routes/{+layout,+page}.svelte`

**Tools / docs:** `tools/enrich/enrich.py` (cascade .env)
