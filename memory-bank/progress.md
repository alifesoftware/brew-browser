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
| **v0.1.0 GitHub release** | ⏸ pending Apple cert install |
| **Phase 9 — Discover category tile UI + Wrong-link** | pending |
| **Phase 10 — Recipes** (multi-package guided installs) | future |

### Test + build status (current)

- `cargo test --manifest-path src-tauri/Cargo.toml`: **204 passed / 0 failed / 6 ignored**
- `cargo check`: clean
- `cargo clippy --all-targets -- -D warnings`: clean
- `npm run build`: clean
- `npm run check`: 0 errors (1 pre-existing tsconfig-node warning)
- `cargo deny check`: advisories ok, bans ok, licenses ok, sources ok
- `cargo tauri build`: produces 6.1 MB unsigned `.dmg`

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
