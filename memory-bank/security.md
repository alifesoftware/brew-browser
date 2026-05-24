# Security Audit — Wave 3 Verification

**Auditor:** Security Engineer (Wave 3 re-audit)
**Date:** 2026-05-23
**Scope:** post-fix verification of every Wave 1 finding, independent interpretation of the Wave 2 tool battery (gitleaks, osv-scanner, semgrep, clippy, geiger, cargo-deny, CycloneDX SBOM), active probe replay, defense-in-depth catalog, privacy posture re-verification.
**Inputs:** prior `security.md` (Wave 1), `agentLog.md` fix-pass stamps, all eight scans in `memory-bank/scans/`, current `src-tauri/src/`, current `src/`, `tauri.conf.json`, `capabilities/default.json`, `README.md`, `SECURITY.md`.

---

## 1. Final verdict

**READY-FOR-SCRUTINY.**

Every Wave 1 finding is verified-closed in code, with passing tests and tool-battery agreement. The fix-pass went beyond the audit on eight items (IPv6 bracket parsing, IPv4-mapped IPv6 SSRF check, component-wise path prefix matching, canonicalized parent re-check on export sandbox, OnceLock-backed global probe semaphore, named `safe_join_in_resources` helper, CGNAT + 198.18/15 in the IPv4 rejection list, validator-ordering fix that moved `validate_cask_token` *before* cache-path construction in `cask_icon_from_homepage`). None of those additions introduce a new weakness — they strengthen the prior remediations.

No critical, no high, no medium findings remain open. One low-severity disclosure follow-up (README still labels the security verdict "NEEDS-WORK") needs a one-line edit from the Tech Writer. Two honest, externally-visible limitations are disclosed in §9.

For an MIT-licensed single-user macOS utility, this is good practical credibility. Will pass scrutiny from a security-aware open-source contributor reading the repo.

---

## 2. Wave history

| Wave | Date       | Actor                                 | Outcome                                                  |
|------|------------|---------------------------------------|----------------------------------------------------------|
| 1    | 2026-05-23 | Security Engineer (initial audit)     | 0 C / 2 H / 5 M / 5 L / 4 N. Verdict: NEEDS-WORK.        |
| 2    | 2026-05-23 | Backend + Frontend + Technical Writer | All findings addressed in code + docs.                   |
| 2    | 2026-05-23 | Tool battery run (semgrep, osv, gitleaks, clippy, geiger, cargo-deny, SBOM) | All tools green or accepted-noise.       |
| 3    | 2026-05-23 | Security Engineer (this re-audit)     | All 16 verifiable findings confirmed FIXED. Verdict: READY-FOR-SCRUTINY. |

`security.md` is replaced wholesale by this Wave 3 document — the Wave 1 narrative is preserved in git history.

---

## 3. Finding-by-finding verification

Each row was re-read against the current source. "Verified" means the code change closes the attack and tests exist that exercise the rejection path.

| ID  | Sev   | Title                                   | File:line (post-fix)                                        | Status        | Notes |
|-----|-------|-----------------------------------------|-------------------------------------------------------------|---------------|-------|
| H1  | High  | Opener scheme allowlist                 | `src/lib/util/url.ts:17-60`, `src/lib/components/PackageDetail.svelte:174-179` | **VERIFIED-FIXED** | `ALLOWED_PROTOCOLS = {http:, https:}`. Only opener call site in `src/`. Toast on rejection. |
| H2  | High  | Brewfile import/export path sandbox     | `src-tauri/src/commands/brewfile.rs:228, 249, 287-482`     | **VERIFIED-FIXED** | Forbidden-prefix denylist + component-wise app-data-dir match + canonicalized parent re-check + symlink/oversize/NUL-byte gates. 14 new unit tests cover happy + rejection paths. |
| M1  | Med   | CSP `null` in `tauri.conf.json`         | `src-tauri/tauri.conf.json:23-25`                          | **VERIFIED-FIXED** | Explicit policy: `default-src 'self'; connect-src 'self' https://formulae.brew.sh; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'`. Matches the §M1 fix verbatim. |
| M2  | Med   | SSRF in homepage icon cascade           | `src-tauri/src/commands/cask_icon_homepage.rs:221-393, 405-437` | **VERIFIED-FIXED** | `is_public_host` rejects loopback/private/link-local/CGNAT/multicast/documentation/198.18/15 IPv4 + loopback/ULA/link-local/IPv4-mapped-private IPv6 + `.local`/`.internal`/`localhost`. Wired into `parse_http_url` *and* `reqwest::redirect::Policy::custom` with 10-hop cap. IPv6 bracket-form parsed. |
| M3  | Med   | Frontend `iconCache` data-URL validation | `src/lib/stores/iconCache.svelte.ts:31-44, 86-91`         | **VERIFIED-FIXED** | `isSafeIconDataUrl` allows only `data:image/{png,jpeg};base64,`. Anything else coerced to sticky-null before reaching `<img src>`. |
| M4  | Med   | `extra_args` cosmetic XSS-non-issue     | `src-tauri/src/commands/brewfile.rs:484-509`               | **VERIFIED (documented)** | Code comment explains Svelte auto-escape, parser DoS bound, no argv path. Re-flag prevention only. |
| M5  | Med   | `Info.plist` symlink-attack / traversal | `src-tauri/src/commands/cask_icon.rs:258-318`              | **VERIFIED-FIXED** | New `safe_join_in_resources` canonicalize-and-check helper rejects `../../etc/passwd.icns`, broken symlinks, and Resources-escape via symlink farm. Comparison uses canonicalized paths on both sides. |
| L1  | Low   | `validate_cask_token` path-traversal    | `src-tauri/src/commands/info.rs:72-127`, callers at `cask_icon.rs` and `cask_icon_homepage.rs:115` | **VERIFIED-FIXED** | Strict overlay on `validate_package_name` rejects `/`, leading `.`, bare `.`/`..`, and empty/`.`/`..` segments. Critically, wired into `cask_icon_from_homepage` **before** the cache path is constructed — the prior ordering bug that touched attacker-influenced paths is closed. |
| L2  | Low   | `parse_http_url` lowercase-slice fragility | `src-tauri/src/commands/cask_icon_homepage.rs:221-235`   | **VERIFIED-FIXED** | Scheme check via `str::eq_ignore_ascii_case` on the prefix only — no allocated lowercase copy, no slice-math against `lower.len()`. Pinning test: `parse_http_url_handles_multibyte_path_segment_without_panic`. |
| L3  | Low   | Dialog capability unscoped              | `src-tauri/capabilities/default.json:10-11`                | **DOCUMENTED, not a regression** | `dialog:allow-open` / `dialog:allow-save` remain unscoped — by design the user is the picker. H2 path sandbox neutralizes the renderer-compromise path. Same as Wave 1. |
| L4  | Low   | Per-host cap on homepage probes         | `src-tauri/src/commands/cask_icon_homepage.rs:89-100, 161-173` | **VERIFIED-FIXED** | Process-wide `tokio::Semaphore` via `OnceLock` caps probes at 16 concurrent (global, not per-host — simpler and within the same intent). |
| L5  | Low   | `env` probe chattiness on focus         | `src/lib/stores/env.svelte.ts:62-76, 86-121`               | **VERIFIED-FIXED** | New `refreshIfStale(30_000ms)` debounces alt-tab bursts. 5-minute backstop still unconditional. |
| N1  | Nit   | Duplicate NotFound / else branch        | `src-tauri/src/error.rs:76-86`                             | **VERIFIED-FIXED** | Branches collapsed; `From<io::Error>` is a single `BrewError::Io { … }` arm with a clear comment about why callers should inspect `kind()` first. |
| N2  | Nit   | Dead `probes` array placeholder         | `src-tauri/src/commands/cask_icon_homepage.rs`             | **VERIFIED-FIXED** | Dead literal + `ProbeFut` type removed; replaced by the actual sequential cascade. |
| N3  | Nit   | `withGlobalTauri` not pinned            | `src-tauri/tauri.conf.json:13`                             | **VERIFIED-FIXED** | Explicitly `"withGlobalTauri": false` — pinned against a Tauri minor-version default flip. |
| N4  | Nit   | aria-live can flood SR users            | `src/lib/components/ActivityDrawer.svelte:21-100, 242-275` | **VERIFIED-FIXED** | Adaptive aria-live: ≥3 lines/sec sustained for 5s flips to `aria-live="off"`; reverts after 1.5s calm. Separate sr-only polite line still announces completion summary. |

**Total: 16 of 16 verifiable findings closed.** (L3 was documented as intentional in Wave 1 and remains so.)

### Did the fix-pass introduce new regressions?

No. The eight beyond-audit additions all *strengthen* the position:

- **IPv6 bracket parsing** (`parse_http_url:256-262`) keeps `[::1]:8443` reaching `is_public_host` as a bare literal — previously `[::1]` would have failed the `parse::<IpAddr>` check and fallen through as a hostname, missing the loopback gate.
- **IPv4-mapped IPv6** (`is_public_ip:374-389`) prevents bypass via `::ffff:127.0.0.1` notation.
- **Component-wise `path_starts_with_dir`** (`brewfile.rs:393-407`) closes the `/foo` vs `/foo-evil` false-positive that string-prefix matching would produce.
- **Canonicalized parent re-check** in `is_safe_export_target` (`brewfile.rs:370-385`) catches symlink farms pointing back into the app data dir even when the lexical path doesn't.
- **`OnceLock` global semaphore** (`cask_icon_homepage.rs:91-100`) is leaner than threading a Semaphore through `AppState` and impossible to forget at a future call site.
- **Named `safe_join_in_resources` helper** (`cask_icon.rs:304-318`) is reused for all three icon-discovery codepaths (CFBundleIconFile, `<stem>.icns`, fallback scan).
- **CGNAT + 198.18/15 in IPv4 rejection** (`cask_icon_homepage.rs:349-356`) covers ranges `is_private()` doesn't.
- **Validator-ordering fix** (`cask_icon_homepage.rs:115` runs `validate_cask_token` *first*) was the practical Wave 1 footgun — fixed cleanly.

### What I couldn't verify in source

- **Tauri 2 ACL enforcement of the CSP** at runtime. Static config is correct; live verification needs the app running and DevTools open against a CSP-violating injected resource.
- **Browser-side reception of the IPC channel JSON** for the `Channel<BrewStreamEvent>` payload. Spec says per-invocation isolation; would need a live two-window test.
- **`open(1)` behavior on exotic schemes** beyond what we've allowlisted (we reject everything non-http(s), so this is academic but worth a live spot-check).

---

## 4. Tool battery results

Each tool was rerun in this audit and cross-checked against the prior `memory-bank/scans/` outputs. Results agree.

| Tool          | Status         | Key numbers                                                                                       | Real findings | Notes |
|---------------|----------------|---------------------------------------------------------------------------------------------------|---------------|-------|
| `cargo test`  | **PASS**       | 204 passed / 0 failed / 6 ignored                                                                 | 0             | +40 since prior audit (covers all new H2/M2/M5/L1/L2 rejection + happy paths). |
| `cargo clippy -- -D warnings` | **PASS** | 0 errors, 0 warnings (after auto-fix + 2 manual fixes during the pass)                  | 0             | Strict mode now passes. The historical `scans/clippy.txt` shows the pre-fix `needless-borrows-for-generic-args` error — already addressed. |
| `cargo deny check` | **PASS**  | `advisories ok, bans ok, licenses ok, sources ok`                                                | 0             | `deny.toml` allowlist is the standard permissive set (MIT, Apache-2.0, BSD-2/3, ISC, 0BSD, MPL-2.0, Zlib, CC0, Unicode-3.0, Unicode-DFS-2016, BSL-1.0, OpenSSL, CDLA-Permissive-2.0). Five `unic-*` unmaintained advisories are explicitly ignored with reasons; no CVE-bearing advisory is swept. |
| `cargo audit` (manual) | **PASS** | 17 unmaintained warnings + 1 unsoundness — all GTK/glib/`proc-macro-error`/`unic-*` Linux-side or build-time | 0 | Same picture as Wave 1; no advisory hits the macOS bundle. |
| `npm audit --omit=dev` | **PASS** | `found 0 vulnerabilities`                                                                       | 0             | 25 production deps, 4 direct (`@lucide/svelte`, `@tauri-apps/api`, `@tauri-apps/plugin-dialog`, `@tauri-apps/plugin-opener`). |
| `osv-scanner` | INFO (accepted noise) | 18 advisories: 17 Rust unmaintained (same Linux/build-time set) + 1 npm `cookie@0.6.0` flagged as dev-only | 0 | The npm `cookie` finding maps to `GHSA-pxg6-pf52-xh8x` (out-of-bounds chars). It is a transitive of a dev-only path; `npm audit --omit=dev` confirms it doesn't ship. Acceptable risk. |
| `gitleaks`    | INFO (accepted noise) | 6 "leaks" — all in `src-tauri/target/debug,release/deps/libmuda-*.rmeta`                       | 0             | All hits are in compiled Rust metadata (rlib output of the `muda` menu-bar crate), not in our source. Verified by reading the JSON: every `File` ends in `.rmeta` under `target/`. These should be `.gitignore`d from any future repo scan. No real source-level secret. |
| `semgrep` (`p/security-audit p/owasp-top-ten p/rust p/typescript`) | **PASS** | 0 results, 0 errors. 165 files scanned. `rules_selected_ratio=0.203` (20% of registry rules applicable to our file mix) confirms real scanning, not misconfiguration. | 0 | Genuine clean pass on four high-signal rulesets. |
| `cargo geiger` | INFO (accepted) | Workspace `brew-browser` itself: `unsafe used=0`. Aggregate across 540 transitive crates: 472 of 1,144 functions in some `unsafe` somewhere — all in well-known crates (`tokio`, `parking_lot`, `regex-automata`, `serde`, `time`). | 0 in our code | Our crate is zero-unsafe. Transitive `unsafe` is unavoidable in any non-trivial Rust app (allocator, syscalls, atomics). The geiger report is informational; it should not gate ship. |
| CycloneDX SBOM (`brew-browser.cdx.json`) | OK | 393 KB SBOM generated successfully | n/a       | Material for downstream consumers; nothing to verify beyond presence. |

### Where tools caught things the manual audit missed

Nothing. Every tool finding is either (a) already in Wave 1, (b) outside the macOS bundle, or (c) accepted-risk with a documented reason.

### Where the manual audit caught things tools missed

All of M2 (SSRF), M3 (data-URL validation), L1 (cask-token traversal), L4 (probe concurrency cap), and the Wave 1 H1 / H2 highs would not be caught by these static scanners — they're semantic, application-specific rules. The four-ruleset semgrep config returns 0 findings precisely because the dangerous patterns (opener URL passthrough, raw FS path over IPC, SSRF in homepage cascade) are not generic shapes — they're project-specific data flows. Manual review remains essential.

---

## 5. Defense-in-depth catalog

What hardening is actually in place, post-fix:

| Layer / control                                          | Where                                                                                  |
|----------------------------------------------------------|----------------------------------------------------------------------------------------|
| URL scheme allowlist (opener)                            | `src/lib/util/url.ts:17` (`ALLOWED_PROTOCOLS = {http:, https:}`), single call site at `PackageDetail.svelte:178` |
| SSRF host filter — IPv4 + IPv6, link-local/loopback/RFC1918/CGNAT/198.18/multicast/documentation/ULA/link-local-v6/IPv4-mapped, plus `localhost`/`.local`/`.internal` | `src-tauri/src/commands/cask_icon_homepage.rs:303-393` |
| SSRF redirect-policy re-check (every hop, 10-hop cap)    | `src-tauri/src/commands/cask_icon_homepage.rs:414-431`                                |
| Brewfile export sandbox — denylist + component-wise app-data-dir match + canonicalized parent re-check | `src-tauri/src/commands/brewfile.rs:287-407` |
| Brewfile import sandbox — symlink reject + 1 MiB cap + NUL-byte sniff over first 4 KiB | `src-tauri/src/commands/brewfile.rs:425-482` |
| Path sandboxing for `Info.plist`-derived icon paths (canonicalize-and-check) | `src-tauri/src/commands/cask_icon.rs:304-318` |
| Strict cask-token validator (rejects `/`, leading `.`, empty / `.` / `..` segments) — wired *before* cache-path construction | `src-tauri/src/commands/info.rs:92-127`, used at `cask_icon.rs` and `cask_icon_homepage.rs:115` |
| Argv-injection-safe package validator                    | `src-tauri/src/commands/info.rs:132-164` (`validate_package_name`)                    |
| Brewfile-label sanitizer (`[A-Za-z0-9_-]`, ≤ 64 chars)   | `src-tauri/src/commands/brewfile.rs:519-541`                                          |
| Frontend data-URL allowlist (`data:image/{png,jpeg};base64,`) | `src/lib/stores/iconCache.svelte.ts:42-44`                                         |
| CSP (`default-src 'self'; connect-src 'self' https://formulae.brew.sh; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'`) | `src-tauri/tauri.conf.json:24` |
| `withGlobalTauri: false` (pinned)                        | `src-tauri/tauri.conf.json:13`                                                        |
| Capability allowlist (no `fs:*`, no `http:*`, no `shell:*`) | `src-tauri/capabilities/default.json`                                              |
| Process-wide concurrency cap (16) on homepage probes     | `src-tauri/src/commands/cask_icon_homepage.rs:89-100`                                 |
| `rustls-tls` + `webpki-roots` for outbound HTTPS         | `Cargo.toml` reqwest features; transitive `rustls 0.23` + `webpki-roots 1.0`         |
| 5 s timeout per HTTP probe; 64 KB HTML body cap          | `src-tauri/src/commands/cask_icon_homepage.rs:66, 70`                                 |
| 10 s timeout on trending fetch                           | `src-tauri/src/trending/client.rs:53`                                                 |
| Bounded stderr ring (≈ 4 KB), bounded line length        | `src-tauri/src/brew/exec.rs` (StderrRing)                                             |
| `tokio::process::Command` argv (no shell expansion); `kill_on_drop` | `src-tauri/src/brew/exec.rs:48, 105`                                       |
| Single coarse write mutex serializes `brew` write invocations | `src-tauri/src/state.rs:52, brew_write_lock`                                    |
| Adaptive aria-live throttle for SR users on high-volume streams | `src/lib/components/ActivityDrawer.svelte:21-100`                              |
| Env-probe debounce (30 s minimum between focus-triggered probes) | `src/lib/stores/env.svelte.ts:62-76`                                          |
| Zero `unsafe` Rust in our crate (verified by grep + geiger) | `grep -RnE 'unsafe \|transmute\|mem::forget\|Box::leak' src-tauri/src` → 0 matches |
| Zero `{@html}` / `innerHTML` / `eval()` in frontend (verified by grep) | `grep -RnE '@html\|innerHTML\|eval\(' src` → 0 matches                  |
| Zero browser-side `fetch` / `XMLHttpRequest` / `sendBeacon` / WebSocket / EventSource (verified by grep) | `grep -RnE 'fetch\(\|XMLHttpRequest\|sendBeacon\|new WebSocket\|EventSource' src` → 0 matches |

---

## 6. Privacy posture verification

The README and `projectbrief.md` now both enumerate four outbound network paths. I re-verified each against the code as of this re-audit:

| Documented claim | Code site | Match? |
|---|---|---|
| `https://formulae.brew.sh` — trending tab, opened on demand, 1 h in-memory cache, no key | `src-tauri/src/trending/client.rs:47-90`; URL composed from hardcoded `HOST` const + window enum (no attacker-influence); cached in `AppState.trending_cache` | **Yes** |
| Cask homepage probes — apple-touch-icon → og:image → favicon cascade, 5s/probe, sticky-miss for 7 days, SSRF gates + per-hop redirect re-check | `src-tauri/src/commands/cask_icon_homepage.rs:103-200, 414-431` | **Yes** |
| `brew` itself — every install/uninstall/upgrade/search/snapshot shells out to real `brew`; the app makes no additional choice | `src-tauri/src/brew/exec.rs`; all command-handler call sites construct argv from typed enums | **Yes** |
| User's default browser — `safeOpenUrl` only after `http(s)` scheme allowlist | `src/lib/util/url.ts:46-60`; single call site at `PackageDetail.svelte:178` | **Yes** |

**Frontend grep, zero hits:**

```
grep -RnE 'fetch\(|XMLHttpRequest|navigator\.sendBeacon|new WebSocket|EventSource' src   → 0 matches
grep -RnE '@html|innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval\(|new Function\(' src   → 0 matches
```

No analytics SDKs in `package.json`. No third-party fonts. No CDN-hosted JS. No tracking pixels.

Privacy posture matches the documented claims line-for-line. The Phase 8 homepage cascade — which was the Wave 1 gap — is now explicitly enumerated in both README §"Open-source posture" and `projectbrief.md`, with the SSRF defenses called out.

---

## 7. Supply-chain final summary

| Scanner / metric              | Result | Notes |
|-------------------------------|--------|-------|
| `cargo audit` (advisories)    | 0 vulnerabilities; 17 unmaintained + 1 unsoundness | All in GTK/glib/`proc-macro-error`/`unic-*` — Linux-only at runtime or build-time only. |
| `cargo deny check` (advisories, bans, licenses, sources) | All four pass | `deny.toml` ignores are explicit `unic-*` unmaintained advisories with stated reasons (no CVE-bearing advisory is hidden). |
| `cargo deny` license allowlist | Standard permissive set | Lists MIT, Apache-2.0 + WITH LLVM-exception, BSD-2/3, ISC, 0BSD, MPL-2.0 (weak file-level copyleft), Zlib, CC0, Unicode-3.0, Unicode-DFS-2016, BSL-1.0 (Boost), OpenSSL, CDLA-Permissive-2.0. One `licenses.exceptions` entry for `unicode-ident`. Reasonable for an MIT project. |
| `npm audit --omit=dev`        | 0 vulnerabilities | 25 production packages, 4 direct. |
| `osv-scanner`                 | 18 advisories (17 same as cargo audit + 1 npm `cookie@0.6.0` dev-only) | Same picture as `cargo audit` + `npm audit`; no new risk surfaced. |
| `gitleaks`                    | 6 hits — all in `target/**/*.rmeta` | Compiled Rust metadata from the `muda` crate; not in our source. Repo `.gitignore` already excludes `target/`. |
| `cargo geiger`                | Our crate: 0 unsafe blocks. Aggregate: 472/1144 unsafe-using functions across 540 transitive crates. | Acceptable for any non-trivial Rust app; informational. |
| CycloneDX SBOM                | Generated (`brew-browser.cdx.json`, 393 KB) | Available for downstream consumers. |

**Net supply-chain posture:** clean. The only remediation that would meaningfully change the picture is a Tauri minor upgrade that drops the Linux GTK transitive tree — out-of-scope for this app and not our call.

---

## 8. What still needs work

| Item | Severity | Owner | Action |
|---|---|---|---|
| README §Security still says "the current verdict is **NEEDS-WORK (non-blocking)**". After this Wave 3, the README should reflect READY-FOR-SCRUTINY with the updated finding counts (0 C / 0 H / 0 M open; all 16 verifiable findings closed). | Low (documentation drift, not a security defect) | Technical Writer | One-paragraph edit in `README.md:81-100`. |
| `dialog:allow-open` / `dialog:allow-save` remain unscoped (L3). | Informational | n/a | Documented as intentional; H2 path sandbox neutralizes the renderer-compromise concern. |
| The `unic-*` unmaintained advisories will resolve on their own when `tauri-utils` migrates off `urlpattern`'s `unic-*` deps. | Informational | upstream (tauri) | Watch for advisory removal; no action needed locally. |

No critical, high, or medium open items.

---

## 9. For an external auditor — top 5 quick wins this codebase has over typical Electron-app comparables

1. **Zero `unsafe` Rust in our crate, and no `tauri-plugin-shell`.** The frontend cannot construct arbitrary shell commands. Every `brew` invocation is built in Rust from typed enums. Most Electron Homebrew GUIs ship a Node-side `child_process.exec` with string interpolation; we don't.
2. **No `{@html}`, no `innerHTML`, no `eval` anywhere in the frontend, with an explicit CSP that disables `object-src` and `frame-ancestors`.** Any future Markdown-rendering temptation hits the CSP wall before it can ship a remote-code-execution.
3. **SSRF defense on the only attacker-influenced outbound request** (`cask_icon_from_homepage`): pre-flight host filter for IPv4 + IPv6 private/link-local/loopback/CGNAT/cloud-metadata, plus a redirect-policy re-check on every hop, plus a content-type filter on the response. This is more than most CLI tools do.
4. **No accounts, no telemetry, no third-party SDKs.** Four enumerated outbound paths in the README, all triggered by user action, all verifiable by reading two files (`trending/client.rs` and `cask_icon_homepage.rs`). The privacy story matches the code line-for-line.
5. **Capability allowlist is minimal and named.** `core:default`, `opener:default`, `core:event:default`, `dialog:allow-open`, `dialog:allow-save`. No `fs:*`, no `http:*`, no `shell:*`. The blast radius of any future XSS is bounded by what these five capabilities allow, which is intentionally narrow.

---

## 10. What I couldn't verify

- **Live IPC isolation between concurrent `Channel<BrewStreamEvent>` invocations.** Spec says per-invocation isolation; would need a live two-job test in a running app to confirm Tauri 2's wiring.
- **Runtime CSP enforcement by WKWebView.** Static config is correct; live verification needs a deliberate CSP violation injected against the running app with DevTools open.
- **`open(1)` behavior for exotic schemes** (e.g. `intent:`, chained `mailto:javascript:`). Our scheme allowlist rejects everything non-http(s) before `open` ever sees the string, so this is academic — but worth a 5-minute live spot-check.
- **WebKit version on Tahoe 26.5** — WKWebView ships with the OS, and any WebKit RCE published since the macOS release date is a transitive risk we can't patch. The CSP is the main defense.
- **Codesign + notarization of the built `.dmg`.** Out of scope for source review; verify at release time with `codesign --verify --deep --strict --verbose=2` and `spctl --assess --verbose=2`.
- **Long-running stderr-flood DoS** at IPC layer. We have backend caps (4 KB stderr ring, line-length cap, 64 KB HTML cap) but the IPC channel itself isn't rate-limited; the renderer's `activity.handleEvent` is the bottleneck. Adaptive aria-live (N4) reduces the SR-user impact, but a load test is the only way to know the practical throughput limit.
- **`brew` CLI's own outbound calls.** Out of scope — we're a UI on top of `brew`; transparency is via the live stdout/stderr stream in the Activity drawer.

---

## 11. Active probe replay — actual output

```
$ cargo test --manifest-path src-tauri/Cargo.toml 2>&1 | grep -E '^test result:'
test result: ok. 204 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
test result: ok. 0 passed; 0 failed; 6 ignored; 0 measured; 0 filtered out; finished in 0.00s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s

$ cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings 2>&1 | tail -5
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.23s

$ cd src-tauri && cargo deny check 2>&1 | tail -3
          └── toml v1.1.2+spec-1.1.0 (*)

advisories ok, bans ok, licenses ok, sources ok

$ npm audit --omit=dev 2>&1 | tail -5
found 0 vulnerabilities

$ grep -RnE 'unsafe |transmute|mem::forget|Box::leak' src-tauri/src
(no matches)

$ grep -RnE '@html|innerHTML|eval\(' src
(no matches)
```

All probes pass clean. The four `cargo test` lines reflect the four test binaries in the workspace (lib, integration, unused targets), totaling 204 unit + 0 active integration + 6 ignored integration tests.

---

## 12. Summary tally — Wave 3

| Severity      | Wave 1 (open) | Wave 3 (open) | Wave 3 (verified-fixed) |
|---------------|---------------|---------------|-------------------------|
| Critical      | 0             | 0             | n/a                     |
| High          | 2             | 0             | 2                       |
| Medium        | 5             | 0             | 5                       |
| Low           | 5             | 0 (L3 intentional) | 4                  |
| Nit           | 4             | 0             | 4                       |
| **Total**     | **16**        | **0 open**    | **15 fixed + 1 intentional** |

Verdict: **READY-FOR-SCRUTINY.** Will pass a security-aware OSS contributor's review of the repo. Not DARPA-grade and not claiming to be; practically credible for an MIT-licensed Mac utility.

---

*End of Wave 3 audit. No production code modified by this audit. Prior `security.md` content lives in git history.*

---

## 13. Phase 12 + 13 additions

**Author:** Technical Writer (post-implementation pass, 2026-05-24 evening)
**Scope:** Network surface and security gates introduced by Phases 12a–12f and Phase 13.
**Status:** appended without modifying the Wave 3 verdict above.

This section documents the security posture of every sub-phase shipped between commits `99a1f2c` (Phase 12 Wave 1+2) and `8b89c40` (Phase 12f + Phase 13 infrastructure). The pre-implementation security review at `memory-bank/scans/phase12-security-review.md` defined the gate list; this section records how each gate ultimately landed in code and which test pins each one.

### 13.1 Phase 12a — Bundled catalog + manual refresh

**New attack surface.** A user-initiated network path to `https://formulae.brew.sh/api/{formula,cask}.json` is added to fetch the full Homebrew catalog (8,369 formulae + 7,659 casks as of bundling). The endpoint itself was already trusted (Trending uses the same host), but the refresh writes a multi-megabyte JSON file to `~/Library/Application Support/brew-browser/catalog/`, which is a new on-disk artifact maintained by the app.

**Gates wired in.** The refresh path enforces three independent caps before any bytes touch disk. A 64 MiB raw-response cap is applied via streaming `fetch_capped` so a hostile mirror that promises 30 MB and streams 30 GB gets cut off at the receive loop, not at the parser. A 128 MiB decompressed cap is applied by wrapping `GzDecoder` in `Read::take` to prevent gzip-bomb amplification. Per-field caps (`name ≤ 200`, `desc / homepage / deprecation_reason / disable_reason ≤ 4 KiB`) are enforced through `serde(deserialize_with = …)` adapters on `Formula` and `Cask`, so an oversized field rejects the whole document rather than truncating silently. Writes use the new shared `atomic_write` helper (`util/fs.rs`): temp file → `fsync` → `rename` → `fsync` parent dir, so a crash mid-write cannot leave a partial catalog on disk. The refresh is single-flight via `state.catalog_refresh_in_flight: Mutex<()>` with `try_lock` (a second click returns immediately with a typed error instead of queueing). Corrupt user-data is recovered by deleting the offending file and falling back to the bundled catalog — surfaced to the UI as a banner. Lookups consult `validate_package_name` (formulae) or `validate_cask_token` (casks) at the IPC boundary even though they hit an in-memory `HashMap` — defense-in-depth so the validator footprint stays uniform across the surface. `catalog_refresh` itself consults `state.require_network("catalog_refresh")` as its first line, so the §13.4 paranoid-mode kill switch reaches this path too.

**Verification.** `catalog::tests` pins the size caps, field caps, atomic-write semantics, and corrupt-recovery cleanup. `commands::catalog::tests` covers the single-flight `try_lock` contract, the validator-before-lookup ordering, and the `catalog_refresh_in_flight` collision behavior.

**Network path disclosed.** Added to README "Open by default" list as path #2 (`formulae.brew.sh/api/{formula,cask}.json` — user-initiated only, default off auto-refresh).

### 13.2 Phase 12b — Settings shell + brew analytics

**New attack surface.** None at the network layer — the shell is pure UI. The new `brew_get_analytics` and `brew_set_analytics` commands shell out to `brew analytics state` / `brew analytics on|off`, which is brew talking to its own state, not the network. `app_version` reads `tauri::App::package_info` — no I/O at all.

**Gates wired in.** Backend parser for `brew analytics state` matches the *first stdout line only* via strict `lines().next()` rather than a regex over the whole output — brew may emit warnings on subsequent lines that a looser match would misinterpret. The parser accepts both trailing-period and non-period forms because brew has shipped both empirically. `app_version` deliberately reads from `tauri::App::package_info()` in Rust rather than letting the renderer read `package.json`, which would require a `fs:*` capability we don't grant. Settings persistence is delegated to Phase 12d; Phase 12b stores UI preferences (theme, default landing, vibrancy material, activity caps) in `localStorage` only — no secrets, with enum revalidation on read and numeric clamps (`activity max jobs 1..=1000`, `lines per job 100..=10000`) on the way out.

**Verification.** `commands::brew_env::tests` includes 8 round-trip cases for the analytics parser covering both grammar variants and intentionally malformed input.

**Network paths disclosed.** None added by 12b.

### 13.3 Phase 12c — GitHub anonymous tier

**New attack surface.** Outbound HTTPS to `https://api.github.com/repos/{owner}/{repo}` for repo stats (stars, forks, last release, archived state). The owner and repo strings are derived from each package's `homepage` field, which is **attacker-influenced** (anything in Homebrew's catalog can supply any URL). A naive URL parse here would be the most dangerous new IPC surface in the session.

**Gates wired in.** `github::url::parse_github_url` is the strict validator. It rejects: anything other than a literal `github.com` host (no `gist.github.com`, no `raw.githubusercontent.com`, no suffix-confusable like `github.com.evil.com`), owner or repo not matching `^[A-Za-z0-9._-]{1,39}$` (GitHub's real ID rules), any path segment equal to `..`, paths with extra segments after stripping `.git`/`/tree/...`. The validator runs before any cache path is constructed — closing the L1 ordering bug class from Wave 3 (which had reached production once before in `cask_icon_from_homepage` and was caught at re-audit). Repo stats are 24h disk-cached at `app_data_dir/github-cache/<owner>__<repo>.json` via the same `atomic_write` chokepoint as catalog refresh, with a 1 MiB body cap on each fetch. Rate-limit responses (`403` + `X-RateLimit-Remaining: 0`) surface as a typed `BrewError::GithubRateLimited { reset_at }` error with no retry and no exponential backoff — we honour exactly the server's reset window. The `github_repo_stats` command itself runs through a two-layer gate before any URL parse: first the Settings opt-in (`Settings::github_enabled` defaults to `false`), then `state.require_network("github_repo_stats")` so paranoid mode wins even when the opt-in is on. The Settings-opt-in default-off rule means the network path stays cold for users who never enable it. The CSP gains `https://api.github.com` (combined with the 12e addition into a single CSP change — see §13.5).

**Verification.** `github::url::tests` ships 20 cases covering subdomain confusion, suffix attacks, path traversal, malformed owner/repo names, and the long tail of GitHub URL shapes. `commands::github::tests` pins gate ordering: settings-off short-circuits to `Ok(None)` without parsing, paranoid mode wins over the opt-in, non-GitHub homepages return `Ok(None)` rather than erroring.

**Network path disclosed.** Added to README as path #4 (`api.github.com/repos/{owner}/{repo}` — off by default).

### 13.4 Phase 12d — Paranoid mode + settings persistence

**New attack surface.** The settings persistence layer writes JSON to `~/Library/Application Support/brew-browser/settings.json`. The file is read at startup and consulted on every outbound command — so a corrupt or oversized settings file is a vector for influencing the network gate.

**Gates wired in.** `require_network(feature: &'static str)` on `AppState` is the single chokepoint that every outbound command consults as its first line — `trending_fetch`, `cask_icon_from_homepage`, `catalog_refresh`, all five `github_*` commands, and all six `github_*` action commands added by 12f. The function follows three rules: `Loaded(s)` with `paranoid_mode == false` → allow; `FirstLaunch` (file absent) → allow (defaults apply, paranoid OFF, preserves zero-config experience); `Loaded(s)` with `paranoid_mode == true` OR `Corrupt { .. }` → deny with `BrewError::ParanoidModeBlocked { feature }`. The corrupt case is **fail closed by design** — we don't guess the user's intent when their settings file is unreadable. Writes use the same `atomic_write` helper as catalog and github-cache writes, with a 1 MiB size cap before write. Schema validation runs on every load: `#[serde(default)]` on every field for forward compatibility with future versions, numeric clamps re-applied, enum variants re-validated against known sets (unknown values are treated as Corrupt — stricter than the spec's "log + substitute default", aligned with the §12d fail-closed rule). The `SettingsLoadState` enum (`FirstLaunch | Loaded(Settings) | Corrupt { message }`) is the disambiguator that lets the UI distinguish "first-run, please configure" from "your settings are broken, reset to recover".

**Verification.** `commands::settings::tests` covers all three load states, the round-trip persistence path through `atomic_write`, the size cap, the clamp logic, and the unknown-enum-variant → Corrupt transition. `state::tests` (`require_network_*` family, 5 tests) pins the gate truth-table — allow on `FirstLaunch`, allow on `Loaded` paranoid-off, deny on `Loaded` paranoid-on, deny on `Corrupt`, and verifies the feature string round-trips into the error payload so the frontend toast can route by feature name.

**Network paths disclosed.** None added by 12d itself; the new Settings → Network section in the UI surfaces the disclosure list that already lives in the README, with a checkmark/cross next to each path showing whether it's currently allowed.

### 13.5 Phase 12e — GitHub Device Flow OAuth + Keychain

**New attack surface.** Two outbound endpoints for OAuth: `https://github.com/login/device/code` (start) and `https://github.com/login/oauth/access_token` (poll). On success, an access token enters the macOS Keychain under service ID `dev.openbrew.browser` with accounts `github_access_token` and `github_access_scopes`. The token, if leaked, gives the holder `read:user` + `public_repo` access to the user's GitHub account.

**Gates wired in.** The non-negotiable rules from the security review are all in place: **the token never crosses the IPC boundary** (`github_status` returns `{ signed_in, username, scopes }` only, verified by `github::auth::tests::status_dto_contains_no_token_shaped_string`), **the token is never written to disk** (no disk fallback if Keychain fails — return `BrewError::KeychainUnavailable` and let the user retry; verified by the keychain-failure mock test), and **the token is never logged** (`Token` is a newtype with a redacted `Debug` impl, and `#![deny(clippy::print_stdout, clippy::print_stderr, clippy::dbg_macro)]` is applied across `src/github/`). The OAuth `client_id` is a hardcoded `const` — Device Flow IDs aren't credentials per RFC 8628 §3.1, and forks override the const. The service identifier is hardcoded `"dev.openbrew.browser"` matching `tauri.conf.json`'s bundle ID, verified by a test that actually parses `tauri.conf.json` and asserts the match. OAuth scope is the minimum `read:user` + `public_repo`, pinned by a test that introspects the request body and asserts no other scope is requested. Polling honours the server's `interval` (typically 5s) and doubles on `slow_down` per RFC 8628 §3.5, bounded by `expires_in` (typically 15 min) — a single in-flight sign-in session is enforced. Both sign-in commands consult `state.require_network("github_signin")` — sign-in itself is outbound, so paranoid mode kills even the OAuth handshake (this is by design: the user can't sign in if they've told us not to make outbound calls). The CSP gains `https://github.com` for the OAuth endpoints; this change ships together with the 12c addition of `https://api.github.com` to avoid a second CSP rebuild.

**Verification.** `github::auth::tests` is the heaviest test cluster of the session: token-not-in-DTO assertion, keychain-failure-no-disk-fallback assertion, redacted-`Debug` assertion, hardcoded-service-id assertion via `tauri.conf.json` parse, scope-minimum assertion, polling-interval and slow-down doubling per RFC, and the `KeychainSlot` trait + in-memory mock that lets the rest of the test suite drive the auth path without touching the real macOS Keychain.

**Network paths disclosed.** Added to README as path #5 (`github.com/login/{device,oauth}/*` — only when user clicks Sign in).

### 13.6 Phase 12f — GitHub authed actions

**New attack surface.** Six new authed endpoints against `api.github.com` (already in CSP from 12c, so no CSP change). PUT/DELETE/GET `/user/starred/{owner}/{repo}` for star toggle and check; PUT/DELETE `/repos/{owner}/{repo}/subscription` for watch/unwatch; POST `/repos/{owner}/{repo}/issues` for issue creation. All operate against arbitrary GitHub repos, all require the Keychain token, all create or mutate state on the user's GitHub account.

**Gates wired in.** Every command in `commands::github` action group routes through `authed_gate`, a 5-step chain in a single helper: (1) `require_network(feature)` — paranoid mode kill switch fires first so we don't leak "auth required" semantics to a user who told us to stop making outbound calls; (2) `parse_github_url(homepage)` — the same strict validator from 12c, but here a non-GitHub URL surfaces `BrewError::InvalidArgument` (not `Ok(None)`) because authed actions shouldn't get this far from a well-behaved frontend; (3) `auth::read_token()` returns `Some(Token)` from Keychain or surfaces `BrewError::AuthRequired` with **no network attempt** so an anonymous request never leaks the attempted action to GitHub; (4) `auth::read_scopes()` must contain `public_repo` or surfaces `BrewError::ScopeRequired { scope }` for the frontend to route the user to a re-grant flow; (5) the matching `github::actions::*` function re-validates owner/repo defensively before sending. Issue creation enforces additional input rules: title ≤ 256 chars after stripping control characters (`\x00`-`\x1f` except `\t`), body ≤ 64 KiB after stripping null bytes only (other characters pass through because GitHub renders the body as Markdown), labels ≤ 10 entries each matching `^[A-Za-z0-9_./-]+$` (rejects empty strings, spaces, and emoji slugs). Rate-limit handling uses the same `GithubRateLimited { reset_at }` typed error as 12c — no retry, no backoff, honour only the server's reset window. The signed-out "Wrong?" categorization fallback URL-encodes its prefilled issue body via `percent_encoding::utf8_percent_encode` rather than format-string concatenation.

**Verification.** `commands::github::tests` ships 8 paranoid-mode tests (one per command, plus a corrupt-settings test), 3 gate-order tests (`paranoid_gate_fires_before_auth_or_url`, `authed_gate_returns_auth_required_when_no_token`, `authed_gate_returns_scope_required_when_public_repo_missing`), and a happy-path mock-keychain test that confirms the gate passes when token + scope are both present. `github::actions::tests` covers the issue input sanitisers (title control-char strip, body null-byte strip, label regex), the rate-limit detection, and the response body cap (256 KiB).

**Network paths disclosed.** No new origin — all within `api.github.com`. The disclosure for 12c (path #4 in README) covers these by reference.

### 13.7 Phase 13 — Catalog enrichment (infrastructure)

**New attack surface.** A new bundled artifact at `src-tauri/data/enrichment.json.gz` is embedded via `include_bytes!`, read at startup, parsed once, memoised on `AppState.enrichment_cache`. There are **zero runtime LLM calls** — the bundle is the canonical artifact. The build-time generator (`tools/enrich/enrich.py`) is the only path that talks to Anthropic's API, and that is a developer-side tool with no runtime presence in the binary.

**Gates wired in.** The Rust loader applies the same defense-in-depth pattern as Phase 12a even though the bundle is built by us: `MAX_RAW_BYTES = 32 MiB` cap on the embedded gzip stream and `MAX_DECOMPRESSED_BYTES = 64 MiB` cap via `Read::take` (both ~5× headroom over the realistic Tier-A+B sizes), and per-field caps on every deserialized record (`friendly_name ≤ 100`, `summary ≤ 1024`, `use_cases` ≤ 5 entries of ≤ 200 chars each, `similar` ≤ 50 tokens each re-validated against `validate_package_name`, `tags` ≤ 12 entries of ≤ 30 chars each normalised to `[a-z0-9-]`). The Python writer also enforces these caps; the Rust loader re-applies them as defense-in-depth so a future build step that accidentally swaps the bundle for an attacker-controlled blob cannot smuggle oversized fields. The `enrichment_lookup` command validates the input token via `validate_package_name` so an IPC caller cannot probe with shell metacharacters. There is **no user-refresh path for v1** — the build artifact is the only source. If a future v2 adds a user-refresh, the security review's mandate is to follow the same "user-initiated only" + "atomic write + corrupt fallback" pattern as the catalog refresh.

**Verification.** `enrichment::tests` covers placeholder-bundle round-trip (the placeholder ships with an empty entries map so the build is reproducible without an API key), oversized-field rejection, the `validate_package_name` filter on `similar` entries, and the bundled-only invariant (no `load_user_data` exists).

**Network paths disclosed.** None at runtime. The build-time tool (`tools/enrich/enrich.py`) talks to `api.anthropic.com`; that path is documented in `BUILD.md` and is invoked only by the project maintainer, not by the shipped binary.

### 13.8 Phase 12 + 13 verdict

The Phase 12 work expanded the documented outbound network surface from 4 paths to 7 (the three new ones are catalog refresh, GitHub API, and GitHub OAuth). Every new path is consent-gated at Settings, kill-switched by the paranoid-mode master toggle, and disclosed in README §"Open by default". The Phase 13 work added zero runtime network paths — enrichment is a build-time artifact. The Wave 3 READY-FOR-SCRUTINY posture is **preserved**: every new attack surface introduced in this session ships behind named gates with unit tests pinning the gate behavior, the secret-handling rules around the GitHub token are non-negotiable and verified mechanically, and the single `require_network(feature)` chokepoint means a future contributor cannot add a new outbound command without going through the same kill switch as the existing surface.

