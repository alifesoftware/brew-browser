# Active Context

**Date:** 2026-05-24 (late session — post-Phase-12g/13b cleanup + UI polish pass)
**State:** Phase 12 (all 6 sub-phases) + Phase 13 infrastructure + Phase 12g/13b cleanup pass + extensive UI polish all complete. Tier A enrichment baked (15,725 entries). 411 tests passing. Working tree has ~40 staged files ready to commit.

## Repo

- **github.com/msitarzewski/brew-browser** — public, MIT, `main` branch
- **Release:** v0.1.0 live at <https://github.com/msitarzewski/brew-browser/releases/tag/v0.1.0>
- 7 commits to date (8th pending — this update):
  - `653e26f` initial release v0.1.0 (186 files)
  - `c72e31d` LLM-generated categories + landing page
  - `2dad9be` drop Caddyfile snippet
  - `cb60e4a` signed + notarized release pipeline
  - `c2ab41f` NEXT-SESSION handoff doc
  - `84ad010` Phase 9 + 11 — Dashboard, Services, donut, category linking, vibrancy
  - `99a1f2c` Phase 12 Wave 1+2 — bundled catalog + Settings + paranoid mode + GitHub anon + Device Flow
  - `8b89c40` Phase 12f + Phase 13 — GitHub authed actions + enrichment infrastructure

## What landed since `8b89c40`

### Tier A catalog enrichment baked
- `python tools/enrich/enrich.py --tier-a` against Anthropic Haiku 4.5
- **15,725 entries** written to `src-tauri/data/enrichment.json.gz` (771 KB compressed)
- Cost: ~$3-5 against user's Anthropic API
- Bundle: 6.1 MiB catalog + 0.74 MiB enrichment = ~6.9 MiB total bundled data
- `tools/enrich/enrich.py` patched: cascade `.env` lookup — falls back to `tools/categorize/.env` so the user doesn't have to duplicate the ANTHROPIC_API_KEY across both tools

### Phase 12g/13b cleanup pass (4 IMPORTANT findings from Code Reviewer)
1. **Phase 12a frontend wired** — `src/lib/stores/catalog.svelte.ts`, `Catalog`/`Formula`/`Cask`/`CatalogSummary` types in types.ts, 6 IPC wrappers in api.ts, Dashboard catalog freshness line, Discover stale-catalog banner (dismissable per-session)
2. **Three persisted settings actually honored:**
   - `trending_ttl_minutes` consumed in `trending_fetch` (was hardcoded 60min)
   - `cask_icon_mode` consumed in `cask_icon_from_homepage` (Off/InstalledOnly/All gate before paranoid check)
   - `catalog_auto_refresh` consumed via new `maybe_auto_refresh_catalog` startup hook + `should_auto_refresh` decision helper; `refresh_catalog_inner` extracted from IPC command for reuse
3. **search-no-match hotfix** — `brew search abcl` had been returning "Search failed: brew_exit_non_zero" because `brew search --cask abcl` exits 1 (formula-only token). `is_brew_search_no_match` helper now tolerates per-kind no-match exits. +4 tests
4. **Phase 13 friendly names rendered in list rows** — Discover (search + chip-filtered), Library (via PackageRow), Trending all show friendly_name as a subtitle below raw token when AI Features is on
5. **+23 backend tests** for settings consumers, +4 for search hotfix, **411 total** (was 385)

### Extensive UI polish pass

**Native macOS menu**
- `tauri::menu` builder in `src-tauri/src/lib.rs` — App menu (About brew-browser / Settings… ⌘, / Hide / Hide Others / Show All / Quit) + Edit + Window submenus
- `on_menu_event` handler emits `menu:about` and `menu:settings` Tauri events
- Frontend `+layout.svelte` listens via `@tauri-apps/api/event::listen` and opens the matching modal
- **Requires app restart to register** (menus build at startup)

**About brew-browser modal** (`src/lib/components/AboutModal.svelte`)
- 🍺 hero + version + brew version + license + repo + AGENCY_AGENTS credit (link to https://github.com/msitarzewski/agency-agents)
- "Donate to the project" CTA → GitHub Sponsors
- "Built with **Agency Agents** — the multi-agent toolkit that orchestrated the waves... powered by Anthropic's **Claude Opus 4.7** and the **Claude Agent SDK**"
- Zero-telemetry posture line at bottom

**GitHub Sponsors setup**
- `.github/FUNDING.yml` → `github: [msitarzewski]` (Sponsor button appears on repo)
- Shared `src/lib/util/donate.ts` exports `SPONSOR_URL = "https://github.com/sponsors/msitarzewski"` (single source for AboutModal + Sidebar)
- Sidebar footer gets a `♥ Donate` link under the brew version

**TopBar — theme + Settings group, top-right**
- New `src/lib/components/TopBar.svelte`
- Theme dropdown (single icon reflecting current theme — sun/moon/monitor — click opens 3-item popover Light/Dark/System with active checkmark)
- Settings gear next to it (Cmd+,)
- `position: absolute` inside `.content` (NOT fixed — keeps it anchored to the main panel area, never overlaps PackageDetail)
- Visual group: subtle sunken background, hair-line divider between buttons, no hard border
- Theme + Settings stripped from sidebar footer

**Unified panel-head styling** (the "precision, happy" pass)
- Global `.panel-head` baseline in `src/app.css` pins height, padding, border-bottom, h1 typography for **every** panel-head — Dashboard / Library / Discover / Trending / Snapshots / Services / Activity AND PackageDetail
- `!important` justified as cross-component layout coordination (each Svelte component has scoped styles)
- `.content .panel-head` scopes the 96px right-padding reserve to main panels only (detail panel doesn't need TopBar reserve)
- Header separators line up perfectly across panels; switching sections no longer makes the bottom border visibly jump

**Responsive headers + columns** (avoid the crashing at narrow widths)
- All panel-heads with right-cluster controls (Trending, Library, Services, ActivityHistory) wrap their Refresh/Clear in `.refresh-wrap` / `.action-wrap`
- `@media (max-width: 1000px)` hides those wraps + auxiliary text ("Updated Ns ago", "N running · M total")
- Refresh/Clear remain available via Cmd+R or per-row actions
- List rows on Trending + Library get two-tier responsive column drops:
  - `@media (max-width: 880px)` drops the trailing 5th column (installed pill / outdated badge)
  - `@media (max-width: 720px)` drops the middle secondary column (Installs / Version)
  - `# / NAME / TYPE` always visible regardless of width
- Plus `overflow: hidden` + `min-width: 0` on every header/row cell so column-header text can't bleed across cells (fixes the NAVME/INVPALLS glyph collision at narrow widths)

**Pillgroup style unified**
- Trending + Library `.pillgroup` lose the hard border; now uses sunken background only (matches the new TopBar group pattern)

**PackageDetail rework**
- h1 renders `enriched?.friendlyName ?? ui.selectedPackage.name`:
  - AI on + enrichment has friendlyName → friendly version is the title; raw token moves to a new "Token" meta row at the top of the dl
  - AI off OR no enrichment → raw token stays as h1 (legacy)
- Type pill right-aligned via `margin-left: auto`
- Close X stays flush at the right edge (now that the global padding-right reserve is scoped to `.content`)
- AI-enriched badge removed from h1 — provenance still surfaces on summary / use_cases / similar / tags lower in the body
- Detail header bottom-border aligns with main panel-head separator to the pixel

**Settings → Brew analytics parser widened**
- `parse_analytics_state` now accepts `[<backend>] [a|A]nalytics are [en|dis]abled[.]` — fixes modern brew's `"InfluxDB analytics are enabled."` output that the original strict matcher rejected as `Internal` error
- Removed redundant `toast.error(...)` on load failure — inline error block already shows the message; toast was stacking
- +3 tests pinning InfluxDB + arbitrary-backend variants

**GitHub sign-in friendlier error**
- `start_device_flow` fails fast with a clear "GitHub sign-in is not configured in this build. See BUILD.md → 'GitHub OAuth App (one-time setup before release)'" message when `GITHUB_OAUTH_CLIENT_ID` is still `Iv1.PLACEHOLDER_REPLACE_BEFORE_RELEASE`
- `github` store uses `brewErrorMessage(e)` instead of `e.code` so the human message reaches the modal
- DeviceFlowModal drops its redundant `toast.error` on error state — modal renders the message inline

**Other small fixes**
- Detail panel closes on any sidebar navigation — `ui.setSection(s)` now also clears `ui.selectedPackage`
- Pillgroup border removed (matches new TopBar pattern)

## Tests & lint (current)

- `cargo test`: **411 passed**, 0 failed, 6 ignored
- `cargo clippy --all-targets -- -D warnings`: clean
- `cargo check`: clean
- `npm run check`: 0 errors, 1 pre-existing tsconfig-node warning
- `npm run build`: clean

## What's queued for the next session (post-compact)

Per the user's plan at compact: **security audit → GitHub OAuth App setup → more UI polish**.

1. **Security audit re-run** against the new code (cargo audit, cargo deny check, npm audit --omit=dev, semgrep, gitleaks). Especially: new `keyring` dep, new `url` dep, new `flate2` dep, `window-vibrancy` dep, native menu code, paranoid-mode wiring, settings persistence, GitHub OAuth flow, enrichment lookup
2. **GitHub OAuth App** — create on github.com/settings/apps with Device Flow enabled, copy client_id, replace `GITHUB_OAUTH_CLIENT_ID` placeholder in `src-tauri/src/github/auth.rs`. Test end-to-end: sign in → status reflects @username → star a package → file an issue → sign out
3. **More UI polish** — open. Probably:
   - Sticky/frozen # + NAME columns at narrow widths (user proposed; deferred from this session)
   - Snapshots panel-head responsive treatment (Import + New Snapshot — primary actions, need icon-only at narrow widths not full hide)
   - Real screenshots per `visualStory.md`
   - Tier B enrichment run (use_cases + similar + tags, ~$15)
   - Address any remaining `codeReview.md` / `accessibility.md` nits

## Memory bank inventory

`toc.md`, `projectbrief.md`, `techContext.md`, `decisions.md`, `activeContext.md` (this), `progress.md`, `systemPatterns.md`, `designSystem.md`, `uxArchitecture.md`, `backendApi.md`, `frontendComponents.md`, `codeReview.md`, `apiTests.md`, `accessibility.md`, `visualStory.md`, `security.md`, `ideas.md`, `phase12-plan.md`, `phase13-plan.md`, `agentLog.md`, `NEXT-SESSION.md`, `scans/{phase12-security-review.md, ...}`, `tasks/2026-05/`.
