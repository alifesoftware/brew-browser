# Tech Context

## Stack

| Layer | Choice | Version |
|-------|--------|---------|
| Shell | Tauri | 2.x |
| Frontend framework | SvelteKit + Svelte | 5.x |
| Frontend language | TypeScript | ~5.6 |
| Build tool | Vite | 6.x |
| SvelteKit adapter | `@sveltejs/adapter-static` (SPA fallback to `index.html`) | 3.x |
| Backend | Rust | 1.95 |
| Async runtime | `tokio` (process, io-util, rt-multi-thread, macros, sync) | 1.x |
| Serde | `serde`, `serde_json` | 1.x |
| Tauri opener plugin | `tauri-plugin-opener` | 2.x |
| HTTP (for trending + GitHub + catalog + updater) | `reqwest` (async, with `rustls-tls` + `webpki-roots` features — no system trust store dependency) | 0.12.x |
| Styling | Plain CSS + design tokens (`src/lib/styles/tokens.css`, `typography.css`, `reset.css`). No utility framework; small custom system per `designSystem.md`. | — |
| Test framework — backend | Rust built-in: `#[test]` for unit, `#[tokio::test]` for async, `#[ignore]` for integration tests that shell out to `brew`. 473 unit tests at v0.3.0. | (stdlib) |
| Test framework — frontend | `svelte-check` against the SvelteKit + TS sources (typecheck only — no Vitest yet; backend is the load-bearing test surface). | 4.x |
| Crypto (updater signature verification) | minisign via `tauri-plugin-updater` 2.x; embedded `UPDATER_PUBKEY` const in `src-tauri/src/lib.rs` | 2.10.x |

## Host environment

- Beast (M5 Max, 128 GB unified memory, macOS Tahoe 26.5)
- Homebrew 5.1.13 with `brew bundle` available
- Node 26.0.0, npm 11.12.1, rustc 1.95.0, cargo 1.95.0

## Files of record

```
brew-browser/
├── LICENSE                          MIT
├── README.md                        loud open-source narrative
├── docs/                            BUILD.md, PLAN.md (phase tracker), PHILOSOPHY.md, release-notes/, icon/, screenshots/
├── package.json                     name=brew-browser
├── src/                             Svelte frontend
│   ├── app.html
│   └── routes/
│       ├── +layout.ts               ssr=false (SPA mode)
│       └── +page.svelte             (default scaffold; replace in Phase 1)
├── src-tauri/
│   ├── Cargo.toml                   name=brew-browser, lib=brew_browser_lib
│   ├── src/
│   │   └── lib.rs                   (default greet command; replace in Phase 1)
│   ├── tauri.conf.json              productName=brew-browser, 1100×720 window
│   └── capabilities/default.json    core:default + opener:default
├── memory-bank/                     this directory
└── static/                          favicon + default logos
```

## Tauri capability allowlist

Currently: `core:default`, `opener:default`.

**Phase 1+ will need:** shell-execute capability for `brew`. Plan: `tauri-plugin-shell` with a strict allowlist permitting only `brew` and `brew bundle` invocations. Alternative: stay within Tauri's built-in command execution via Rust (`tokio::process::Command::new("brew")` from inside Tauri commands, no shell plugin needed because the IPC boundary stops the frontend from passing arbitrary arg vectors). **Prefer the Rust-only path** — keeps the attack surface tighter.

## Frontend → Backend IPC

Pattern: `import { invoke } from "@tauri-apps/api/core"` on the frontend, `#[tauri::command]` on the Rust side. Long-running commands stream output via Tauri's event channel (`app.emit_to(<window>, <event-name>, payload)` in Rust; `listen(eventName, callback)` in JS).

## Brew interaction patterns

All `brew` calls go through `tokio::process::Command::new("brew")`. Use `--json=v2` wherever supported (`brew list`, `brew info`, `brew search`). For streaming commands (`install`, `uninstall`, `upgrade`), stream stdout+stderr line-by-line to the frontend via Tauri events.

Serialize concurrent `brew` invocations using a `tokio::sync::Mutex<()>` in Tauri's managed state — `brew` does NOT tolerate concurrent operations against its own state.

## Trending data source

`https://formulae.brew.sh/api/analytics/install/30d.json` (and `90d`, `365d` variants). Public Homebrew-maintained JSON. No auth required. Cache in memory ~1 hour to avoid hammering.

## Known sharp edges

- **Tauri sandbox vs. shell execution** — explicit allowlist in `tauri.conf.json` is required to permit any subprocess
- **Cask installs may prompt for sudo** — `brew install --cask` sometimes invokes macOS installer; we surface stdout verbatim and document the limitation
- **`brew bundle dump` is slow on large libraries** — needs progress feedback
- **`brew search` is slow on cold cache** — show loading state, cache for the session
- **SvelteKit with `adapter-static` requires `ssr=false`** — already configured in `+layout.ts`
