# Active Context

**Date:** 2026-05-24
**State:** Public on GitHub. Landing page deployed to umbp. Categorize bulk run completed. Awaiting Apple Developer cert install for signed v0.1.0 release.

## Repo

- **github.com/msitarzewski/brew-browser** — public, MIT, `main` branch
- 3 commits to date:
  - `653e26f` feat: initial release — brew-browser v0.1.0 (186 files)
  - `c72e31d` data: initial LLM-generated package categories + landing page
  - `2dad9be` landing: drop Caddyfile snippet, defer config to manual
- 2 commits worth of additional work staged but not yet committed (this memory-bank sync + new social card when user provides it)

## Bulk categorize run — done

- **15,974 packages** categorized (7,607 casks + 8,367 formulae)
- **$1.50** spent against Anthropic API
- Model: `claude-haiku-4-5`
- 838 KB `src-tauri/data/categories.json` committed to repo
- Avg 1.22 categories per item: 12,511 single, 3,443 double, 20 triple
- Top categories: developer-tools (6,479), graphics (3,086), system-utilities (2,078), cloud-devops (1,228), security (1,040)
- Future delta runs via cron in `tools/categorize/` — daily diff against fresh fetch, only re-categorize new/changed tokens. ~$0.01 per delta run.

## Landing page — deployed

- Live at `brew-browser.zerologic.com` (Caddy config handled manually by user)
- Source in `landing/` (in-repo, versioned)
- Files: `index.html` (10 KB, full SEO + OG + Twitter + JSON-LD + PWA manifest), `style.css` (7.4 KB, OKLCH tokens matching the app), `brew-browser.svg`, `manifest.json`, `robots.txt`, `sitemap.xml`, `social-card.png` (1200×630), `social-card.svg` (source)
- Deployed via `rsync -avz --delete --exclude README.md ./ michael@100.98.187.7:Sites/brew-browser/`
- Updates: same rsync command, re-run on edit

## Social card iteration history

User went through several iterations on the social card. Final answer: **split layout, dark left + light right, with a beer-mug icon variant** (different from the master icon's hop-leaf-in-magnifier design). The user has the final PNG in their clipboard / screenshot temp; pending save to a persistent path so we can drop into `landing/social-card.png`.

Note: the master icon at `docs/icon/brew-browser.svg` is still the **hop-leaf** design (MD5 `0f066349ad5b2e80cd562c65a4731a76`). The user appears to have iterated to a beer-mug variant for the social card; whether to swap the master too is open.

## Apple Developer signing — pending user action

- User has Apple Developer membership
- Beast's keychain has **0 valid codesigning identities** as of last check
- Needs: download a "Developer ID Application" certificate from developer.apple.com → install in keychain
- Then I wire up `tauri.conf.json` (signing identity, hardened runtime, notarization env vars) and rebuild a signed + notarized `.dmg`
- After that: `gh release create v0.1.0 …` with the signed `.dmg` attached

## Ideas captured (in `ideas.md`)

- **Recipes** — guided multi-package install flows ("Want local inference? Let's check your specs, here's what fits"). High signal. Maps cleanly onto existing primitives.
- **GitHub OAuth (optional)** — power-user shortcut for "Wrong?" categorization reporting, star repo from app, bug-report with system info. Strictly optional, no nag.
- **Liquid Glass / NSVisualEffectView (Phase 9 polish)** — discussed. Tier A (NSVisualEffectView via `tauri-plugin-window-vibrancy`, ~30 min, works on macOS 13+). Tier B (true Tahoe Liquid Glass via Swift bridge, half-day, Tahoe-only). Recommend deferring to v0.2.0.
- Discovery UI surface: chip filters on Library + Trending too (not just Discover), category tile grid, app-icon thumbnails in tiles, search-within-category, multi-select intersection, "what's new this week" pulled from cron diff, per-cask "similar to"

## What's done in code

| Phase | Status |
|-------|--------|
| 0 — Scaffold | ✅ |
| 1 — Library (read-only) | ✅ |
| 2 — Discover (search) | ✅ — categories tile UI not built yet |
| 3 — Install/Uninstall/Upgrade w/ streaming | ✅ |
| 4 — Snapshots (Brewfile dump/install) | ✅ |
| 5 — Polish + `.dmg` build artifact | ✅ (unsigned) |
| 6 — Trending tab | ✅ |
| 7 — Cask icons (installed extraction) | ✅ |
| 8 — Cask icons (homepage cascade for uninstalled) | ✅ |
| Security audit + fix-pass + tool battery + re-audit | ✅ READY-FOR-SCRUTINY |
| Reframe — drop counter-narrative | ✅ |
| Categorize tool + first bulk run | ✅ |
| Landing page + SEO/social treatment | ✅ — pending final social card |

## Pending (in priority order)

1. **Apple Developer cert install** on Beast (user action) → wire signing → rebuild signed `.dmg` → tag + push v0.1.0 release with `.dmg` attached
2. **Save new social card PNG** to persistent path so it can replace `landing/social-card.png` and re-rsync to umbp
3. **Decide:** swap the master icon SVG to the beer-mug variant the user prefers? Affects `docs/icon/brew-browser.svg`, `src-tauri/icons/`, app rebuild
4. **Phase 9 build:** Discover category tile grid + filter wiring + "Wrong?" GitHub-issue deeplink against the now-complete `categories.json`
5. **Recipes core** (Phase 10): library + apply-and-stream flow + 5 starter recipes

## Memory bank inventory

`toc.md`, `projectbrief.md`, `techContext.md`, `decisions.md`, `activeContext.md` (this), `progress.md`, `systemPatterns.md`, `designSystem.md`, `uxArchitecture.md`, `backendApi.md`, `frontendComponents.md`, `codeReview.md`, `apiTests.md`, `accessibility.md`, `visualStory.md`, `security.md`, `ideas.md`, `agentLog.md`, `tasks/2026-05/`, `scans/`.
