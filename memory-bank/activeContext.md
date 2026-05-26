# Active Context

**Date:** 2026-05-26 (v0.4.0 Steps 1–8 done on branch; only Step 9 — Caddy deploy — remaining)
**State:** Full v0.4.0 backend + frontend + collector + docs landed on branch `feat/v0.4.0-velocity-and-history`. Three commits ahead of `main`: backend (`3f576b8`), frontend (`6711133`), collector (`6901b64`); a fourth commit covering docs/memory-bank polish is being prepared now. The remaining work is operational — Caddy reload on `brew-browser.zerologic.com` + seed.js bootstrap + curl verification (all documented in `security.md` §16.6). From this branch onward, merges to `main` go through PRs.

## Repo

- **github.com/msitarzewski/brew-browser** — public, MIT
- **Released:** v0.1.0, v0.2.0, v0.2.1, v0.3.0, v0.3.1 (live on GitHub Releases — `gh release list`)
- **Working toward:** v0.4.0 (single coherent release; on branch, ready to PR after Step 9 deploy verification)
- **Branch:** `feat/v0.4.0-velocity-and-history` (off `main` at `d6d28a0`)
- **Stars:** 18 (as of v0.3.1 ship)

## What landed this session (uncommitted, on the branch)

Full v0.4.0 app+infra+docs. Detail in `tasks/2026-05/19-v0.4.0-backend.md`.

### Backend (Steps 1–3) — commit `3f576b8`

- `Settings.enhanced_trending_enabled: bool` (default `false`, forward-compat tested)
- `state::AppState::require_enhanced_trending()` composing paranoid gate + per-feature toggle
- `BrewError::FeatureDisabled { feature }` variant (distinct from `ParanoidModeBlocked` for toast routing)
- Parallel `install` + `install-on-request` fetch via `tokio::join!`
- Pure-math `velocity_index(c30, c90, c365) → Option<f64>` helper
- Server-side velocity back-fill from 3-window join via `tokio::task::JoinSet`
- `TrendingEntry` extended with optional `install_on_request_count{,_formatted}` + `velocity_index` (`skip_serializing_if`)
- New `trending::history::{mod, client, cache}` module backing `trending_history_index` + `trending_history_fetch` IPCs
- Per-package LRU cache (cap 500, TTL 6h)
- Path-traversal-safe URL builder (strict `[A-Za-z0-9._+@-]+` allowlist)
- +33 tests (473 → 506). `cargo build` clean.

### Frontend (Steps 4–6) — commit `6711133`

- `SettingsSectionTrendingHistory.svelte` (NEW) opt-in subsection mounted alongside the Updates subsection at the bottom of Network
- 6th `pathStatuses` entry in `SettingsSectionNetwork.svelte` for the new endpoint
- `Settings.enhancedTrendingEnabled` + `feature_disabled` `BrewErrorPayload` variant in `types.ts`
- `Trending.svelte` defaults to sort-by-velocity desc; new Velocity column with Flame/Snowflake/dash badges; count cell becomes vertical-flex with inline `TrendingSparkline` beneath the formatted number (when enhanced trending is on); 8-col responsive grid
- `TrendingSparkline.svelte` (NEW) shared SVG component with `inline` (60×16) and `detail` (360×80 with current-dot) variants
- `trendingHistory.svelte.ts` (NEW) store with index + per-package series caches and sync lookups
- `PackageDetail.svelte` mounts a `detail`-variant sparkline in a new `trend-card` section between description and AI blocks; strictly passive (no placeholder when toggle off per D4)
- `npm run check`: 0 errors, 3 pre-existing warnings (same as v0.3.1 baseline)

### Collector for brew-browser.zerologic.com (Step 7) — commit `6901b64`

- `tools/trending-collector/` (NEW directory): plain Node 20+ ESM, single dependency `better-sqlite3`
- `lib/common.js` — SQLite schema + HTTP helpers + velocity math (mirrors Rust) + atomic JSON writes
- `lib/render.js` — regenerates `index.json` (top-500 by velocity + ~30-day inline sparklines) + per-package files
- `seed.js` — one-shot bootstrap deriving three historical buckets per package via rolling-window subtraction
- `collect.js` — nightly cron entrypoint, 12 concurrent endpoint fetches, idempotent
- `README.md` — full deploy walkthrough (layout, ssh+rsync, npm ci, run seed.js once, cron line, Caddy config reference)

### Memory bank + docs (Step 8) — pending commit

- `projectbrief.md` — nine → ten outbound paths (item j = the opt-in endpoint)
- `decisions.md` — new ADR `2026-05-26: Opt-in trust boundary for enhanced trending history (v0.4.0)`
- `security.md` §16 — full endpoint audit with actual Caddyfile snippet + threat-model table + pre-launch checklist
- `techContext.md` — Trending data sources section rewritten for both always-on + opt-in endpoints
- `backendApi.md` §13.14 — v0.4.0 backend surface documented
- `frontendComponents.md` — new v0.4.0 additions block
- `docs/release-notes/0.4.0.md` (NEW) — user-facing release notes
- `README.md` — outbound paths disclosure: nine → ten; path (a) rewritten with `install-on-request` + velocity; new path (j) entry

## What's left

Just **Step 9** — Caddy deploy on `brew-browser.zerologic.com` (verbatim config in `security.md` §16.2), then the pre-launch curl-verification checklist (`security.md` §16.6), then the bootstrap run (`node seed.js` on the box), then the PR into `main`, then v0.4.0 release.

The user's call on whether to:
- **(a)** Do Step 9 from this checkout via ssh (deploy + verify + bootstrap)
- **(b)** Hand off Step 9 to a separate session and merge this branch as a PR first (Step 9 becomes a follow-up commit on `main` or a separate branch)
- **(c)** Pause until ready to ship — branch sits with everything except the operational deploy

## Tests & lint (current)

- `cargo test`: **506 passed**, 0 failed, 6 ignored (473 → 506, +33 new)
- `cargo build`: clean, zero dead-code warnings (every new symbol is wired and exercised)
- `npm run check`: 0 errors, 3 pre-existing warnings (same as v0.3.1 baseline)
- `node --check` on every collector .js file: clean

## Workflow change (durable)

From this branch onward, merges to `main` go through pull requests — push branch, `gh pr create`, review/CI, merge. No more direct pushes to `main`. (Persisted in `~/.claude/projects/-Users-michael-Clean/memory/feedback_pr_workflow.md`.)

## Memory bank inventory

`toc.md`, `projectbrief.md`, `techContext.md`, `decisions.md`, `activeContext.md` (this), `progress.md`, `systemPatterns.md`, `designSystem.md`, `uxArchitecture.md`, `visualStory.md`, `backendApi.md`, `frontendComponents.md`, `codeReview.md`, `apiTests.md`, `accessibility.md`, `realityCheck.md`, `security.md`, `ideas.md`, `agentLog.md` (dormant), `NEXT-SESSION.md`, `tasks/2026-05/` (19 task records + README + deferred), `phases/`, `scans/2026-05-23/`.
