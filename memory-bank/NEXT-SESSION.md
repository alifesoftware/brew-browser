# NEXT-SESSION handoff — read this first

**Date written:** 2026-05-24
**Session lead:** Claude Opus 4.7 (1M context) with Michael

If you're a fresh session (or future-me after a /compact), read this first, then `activeContext.md`, then `progress.md`. They tell you everything that's been built. This file just tells you what's queued and how to pick up cleanly.

---

## Immediate state

**The signed + notarized v0.1.0 `.dmg` exists and verifies clean.**

- Path: `src-tauri/target/release/bundle/dmg/brew-browser_0.1.0_aarch64.dmg`
- Size: 5.7 MB
- Signed by: `Developer ID Application: Michael Sitarzewski (7JQGQ7CRH8)`
- Notarized + stapled (verified via `spctl --assess` and `xcrun stapler validate`)
- Gatekeeper-clean: a downloader gets no warning

**Everything else is pushed to `main` on github.com/msitarzewski/brew-browser.** Last commit: `cb60e4a`.

---

## Decision pending before v0.1.0 release

User asked "Pretty sure the icons are right now?" at session end. Verify:

- **Current master icon at `docs/icon/brew-browser.svg`** is the **hop-leaf-in-magnifier** design (squircle + window chrome + silver magnifier whose lens contains a green hop cone). MD5: `0f066349ad5b2e80cd562c65a4731a76`.
- **This is the icon baked into the signed `.dmg`.** A preview of `src-tauri/icons/icon.png` (512px) was sent for the user to visually confirm at session close.
- A **separate beer-mug-in-window icon variant** has been used in social-card iterations. It's NOT the master. User has the PNG but never provided a corresponding SVG.

**If user confirms the hop-leaf is right** → tag and release immediately (see "Release commands" below).

**If user wants the beer-mug** → they need to drop the SVG somewhere (e.g. `~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/brew-browser-icon.svg`), THEN:
1. Copy to `docs/icon/brew-browser.svg`
2. Re-rasterize: `qlmanage -t -s 1024 -o /tmp docs/icon/brew-browser.svg && mv /tmp/brew-browser.svg.png docs/icon/preview-1024.png`
3. Re-mint: `npm run tauri icon docs/icon/preview-1024.png`
4. Rebuild + re-sign: `source ~/.config/brew-browser/signing.env && ./tools/build/sign-and-notarize.sh`
5. Then release

---

## Release commands (once icon is confirmed)

```sh
cd /Users/michael/Clean/brew-browser

# Draft the release notes — content suggestion below
cat > /tmp/v0.1.0-notes.md <<'EOF'
# brew-browser v0.1.0 — initial release

Native macOS GUI for Homebrew. Browse, search, install/uninstall/upgrade
with live streaming output, snapshot to Brewfile and restore, browse
trending packages from Homebrew's published analytics.

## What's in this release

- 5 sidebar sections: Library / Discover / Trending / Snapshots / Activity
- Cmd+K command palette, Cmd+1…5 navigation, drag-resizable detail pane
- Cask icons from installed `.app` bundles or homepage cascade
- Brewfile snapshot/restore via `brew bundle`
- Trending tab via `formulae.brew.sh` 30/90/365-day analytics
- 15,974 packages pre-categorized via `tools/categorize/`

## Posture

- MIT licensed, full source
- 0 critical / 0 high / 0 medium / 0 low security findings
  (`cargo audit`, `npm audit`, `osv-scanner`, `cargo deny`, `semgrep`,
  `gitleaks`, `cargo clippy -D warnings` — all clean)
- Zero `unsafe` Rust, no `tauri-plugin-shell`
- Four documented outbound network paths (see README "Open by default")

## Install

Download `brew-browser_0.1.0_aarch64.dmg` below, open, drag to
Applications. Signed and notarized — no Gatekeeper warning.

Apple Silicon only for now. macOS 13+.

## Build from source

See README + `BUILD.md` in the repo.
EOF

# Create the release with .dmg attached
gh release create v0.1.0 \
  --target main \
  --title "v0.1.0 — initial release" \
  --notes-file /tmp/v0.1.0-notes.md \
  src-tauri/target/release/bundle/dmg/brew-browser_0.1.0_aarch64.dmg
```

After release: the README's "Coming soon: `brew tap msitarzewski/brew-browser`" line should be replaced with the actual install instructions (cask formula pointing at the release asset). That's a follow-up commit.

---

## What's queued for Phase 9+

In rough priority order. Each is its own session's work, not blocking v0.1.0:

1. **Discover category tile UI** — wire `src-tauri/data/categories.json` (15,974 items) into a tile grid in the Discover tab. Tiles use Lucide icons from `categories[slug].icon`. Click tile → filtered list. Tile design: icon + label + count badge. ~half day of agent work.

2. **"Wrong?" GitHub-issue link** in PackageDetail — small Svelte addition. Click opens default browser to a pre-filled issue URL on the brew-browser repo with token name + current categories. ~30 min.

3. **Category filter chips on Library + Trending too** — same data, same UX. ~hour.

4. **Recipes** (the user's "ideas.md" headliner) — guided multi-package install flows. "Set up local inference / web dev / podcast editing." Pre-flight specs check, then `brew bundle`-style apply with the existing streaming Activity drawer. Recipes stored as YAML/JSON in `src-tauri/data/recipes/`, contributor-friendly. Maps cleanly onto existing primitives. ~1-2 days for the core + 5 starter recipes.

5. **Optional GitHub OAuth** — Device Flow for "Wrong?" reporting / star-the-repo / bug-report-with-system-info. Strictly opt-in, no nag. Per the no-accounts posture, must feel like a power-user shortcut. ~half day with the right Tauri community plugin.

6. **Tier A NSVisualEffectView (vibrancy)** — `tauri-plugin-window-vibrancy` for native macOS translucent sidebar/window background. ~30 min for the wiring, but triggers a fresh accessibility audit on the now-translucent surfaces. Phase 9 polish.

7. **Real screenshots** for README + landing page per `visualStory.md` — 30-min manual shoot, fill in `docs/screenshots/library-dark.png` etc.

8. **brew bundle error UX polish** — friendlier toast composition for the known `shivammathur/extensions/imap-uw` Ruby panic. Small. Currently surfaces verbatim Ruby stack with a generic "brew_exit_non_zero" header.

9. **Categorize cron on Beast or umbp** — daily 3am `python categorize.py` to pick up new/changed Homebrew tokens. Currently only the bulk run has executed. Trivial: `crontab -e` + the line from `tools/categorize/README.md`.

10. **Address remaining `codeReview.md` important + nit items** (10I + 11N) — many superseded by Phase 7/8/security work, due for re-audit.

11. **Address remaining `accessibility.md` important + nit items** (9I + 8N) — same.

---

## How agents collaborate on this project (reminder)

Per `memory-bank/toc.md`:

- Each agent reads `projectbrief.md`, `techContext.md`, `decisions.md`, `activeContext.md` before doing anything
- Each agent writes ONLY to its owned files (per the file table in `toc.md`)
- Architectural decisions → ADRs in `decisions.md`
- Cross-cutting patterns → `systemPatterns.md`
- New file additions → `frontendComponents.md` / `backendApi.md` as appropriate
- Every agent run appends a one-line stamp to `agentLog.md` on completion

When starting a new session, the recommended wave structure for any non-trivial work:
- **Wave 1: design** — UI Designer / UX Architect / Backend Architect produce specs (parallel)
- **Wave 2: implementation** — Backend Architect + Frontend Developer build against specs (parallel)
- **Wave 3: validation** — Code Reviewer + API Tester + Reality Checker (parallel)
- **Wave 3.5: fixes** — same agents apply the validation findings
- **Wave 4: polish** — Whimsy Injector + Technical Writer + Accessibility Auditor + Visual Storyteller (parallel)

---

## Credentials / paths reference

| What | Where |
|------|-------|
| Repo on disk | `/Users/michael/Clean/brew-browser/` |
| GitHub repo | `github.com/msitarzewski/brew-browser` |
| Anthropic API key (for categorize tool) | `tools/categorize/.env` (gitignored, user's local) |
| Apple signing env | `~/.config/brew-browser/signing.env` (0600 perms, outside repo) |
| Signed .dmg artifact | `src-tauri/target/release/bundle/dmg/brew-browser_0.1.0_aarch64.dmg` |
| Landing page (deployed) | `brew-browser.zerologic.com` (served from `~/Sites/brew-browser/` on umbp via Caddy, user-managed) |
| umbp Tailnet IP | `100.98.187.7` |
| Local SSH alias | doesn't resolve; use the tailnet IP |

## Open security note

The Anthropic API key in `tools/categorize/.env` and the app-specific Apple password in `~/.config/brew-browser/signing.env` are **valid and live**. If the user ever shares this conversation transcript publicly, both should be regenerated (free, takes <1 min each):

- Anthropic: console.anthropic.com → API keys → revoke + create new
- Apple: appleid.apple.com → Sign-In and Security → App-Specific Passwords → revoke + generate new

Reminder was given at session close; user may or may not have acted.
