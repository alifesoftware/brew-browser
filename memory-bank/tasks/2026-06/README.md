# Tasks — 2026-06

Per-task records for June 2026 work on brew-browser.

## Index

| # | Task | Date | Branch | Release |
|---|---|---|---|---|
| 01 | [Tauri←native feature parity (icons, Dashboard charts, keychain one-prompt, velocity threshold)](./01-tauri-native-parity.md) | 2026-06-02 | `tauri-parity` | — |

## Context

The `experiment/native-swift-liquid-glass` rebuild (native macOS 26 app under `native/`) raced ahead in a few areas. Per the parity charter (`decisions.md` 2026-06-01 + memory `project-parity-charter`), feature/data-contract work is kept in sync across the two builds. This month's first task brings the shipped **Tauri** app up to the native build's treatment of list/detail icons and the Dashboard charts, consolidates the GitHub Keychain reads to a single prompt (mirroring native), and reconciles the Trending velocity badge threshold to a single canonical rule. The reverse direction (native←Tauri: legend icons, banded velocity, Snapshots/Services) is tracked separately.
