//! Friendly error mapping for known upstream Homebrew bugs.
//!
//! Some `brew` failures are not user error — they're upstream Homebrew Ruby
//! bugs (e.g. `bundle/brew.rb:686 Homebrew::Bundle::Brew::Topo#tsort_each_child`
//! exploding on certain tap-formula combinations). Surfacing the raw
//! `BrewExitNonZero { code, stderr_excerpt }` to the toast layer is technically
//! honest but unhelpful: the user has no way to know "this is a brew bug, not
//! your Brewfile."
//!
//! This module pattern-matches the captured stderr against a small, hand-
//! curated catalog and returns a one-sentence friendly message when a known
//! pattern hits. The full stderr is still preserved in the original error
//! variant and shown verbatim in the Activity drawer — `friendlify` only
//! drives the toast.
//!
//! **Polish, not a rules engine.** Keep the catalog tiny (three or four
//! patterns max). When in doubt, return `None` and let the generic error
//! surface unchanged.

/// Return a friendly one-sentence message if `stderr_excerpt` matches a known
/// upstream-bug pattern for the given `command`. Returns `None` when nothing
/// matches — callers should fall back to the generic error rendering.
///
/// `command` is the user-facing form (e.g. `"brew bundle dump --file=… --force"`).
/// We use it to gate patterns to specific subcommands (bundle-only patterns
/// shouldn't fire on `brew install`).
///
/// `stderr_excerpt` may be the bounded ring snapshot from `run_brew_streaming`
/// — up to ~4 KB — so pattern checks must be cheap substring scans, not
/// regex. UTF-8 multibyte content is safe: `str::contains` operates on bytes
/// but `&str` itself is always valid UTF-8.
pub fn friendlify(stderr_excerpt: &str, command: &str) -> Option<String> {
    let is_bundle = command.contains("bundle dump") || command.contains("bundle install");

    // Pattern 1 — `brew bundle` topo-sort key-not-found.
    //
    // Real failure shape (verified 2026-05-23, brew 5.1.13):
    //   Error: key not found: "shivammathur/extensions/imap-uw"
    //   /opt/homebrew/Library/Homebrew/bundle/brew.rb:686:in
    //     'Homebrew::Bundle::Brew::Topo#tsort_each_child'
    //
    // This is an upstream Homebrew Ruby bug, reproducible outside our app.
    // Both substrings must be present so we don't false-positive on unrelated
    // "key not found" messages.
    if is_bundle
        && stderr_excerpt.contains("key not found:")
        && stderr_excerpt.contains("Homebrew::Bundle::Brew::Topo")
    {
        return Some(
            "Homebrew's `brew bundle` hit an internal topo-sort error on one of \
             your installed formulae. This is an upstream Homebrew bug, not a \
             brew-browser issue. Try `brew untap` on a recently-added tap, or \
             see the full output in Activity."
                .to_string(),
        );
    }

    // Pattern 2 — Homebrew explicitly asks the user to report the issue.
    //
    // Real failure shape: brew prints
    //   Please report this issue:
    //     https://docs.brew.sh/Troubleshooting
    // on any internal Ruby exception. Surfacing the friendly hint nudges the
    // user toward Homebrew's troubleshooting docs instead of blaming us.
    if stderr_excerpt.contains("Please report this issue:")
        && stderr_excerpt.contains("docs.brew.sh/Troubleshooting")
    {
        return Some(
            "Homebrew reported an internal error and asked you to report it \
             upstream. See the full output in Activity, and visit \
             https://docs.brew.sh/Troubleshooting for next steps."
                .to_string(),
        );
    }

    // Pattern 3 — `brew services start|stop|restart` failed because the
    // service plist lives in a launchd domain that the current user
    // session does not own (user vs. system launchd domain, a common
    // Sonoma+ failure mode). The stderr shape we key on:
    //
    //   Could not find service "ollama" in domain for current user
    //   (gui/501/...). Run `launchctl bootstrap` with the right
    //   domain, or move the plist to ~/Library/LaunchAgents.
    //
    // We match on the first line of the canonical upstream message.
    // The command is matched on `services` so we don't fire on every
    // unrelated "domain" mention.
    if command.contains("services")
        && (stderr_excerpt.contains("Could not find service")
            || stderr_excerpt.contains("not found in domain"))
    {
        return Some(
            "brew could not find this service in the current launchd \
             domain. The plist is likely registered for a different user \
             or session. Try `brew services restart`, or move the plist to \
             ~/Library/LaunchAgents and run `launchctl bootstrap gui/$UID`."
                .to_string(),
        );
    }

    None
}

// ---------- Tests ----------

#[cfg(test)]
mod tests {
    use super::*;

    /// Captured from a real `brew bundle dump --force` run on a machine with
    /// the `shivammathur/extensions/imap-uw` tap-formula installed.
    const REAL_TOPO_STDERR: &str = r#"Error: key not found: "shivammathur/extensions/imap-uw"
/opt/homebrew/Library/Homebrew/bundle/brew.rb:686:in 'Homebrew::Bundle::Brew::Topo#tsort_each_child'
/opt/homebrew/Library/Homebrew/vendor/portable-ruby/3.3.5/lib/ruby/3.3.0/tsort.rb:413:in 'block in each_strongly_connected_component'
"#;

    const REAL_REPORT_STDERR: &str = r#"Error: undefined method 'foo' for nil:NilClass
Please report this issue:
  https://docs.brew.sh/Troubleshooting

These open issues may also help:
  https://github.com/Homebrew/brew/issues
"#;

    // ---- positive matches ----

    #[test]
    fn topo_sort_pattern_matches_on_bundle_dump() {
        let msg = friendlify(REAL_TOPO_STDERR, "brew bundle dump --file=/tmp/x --force")
            .expect("topo-sort pattern should match real stderr on `bundle dump`");
        assert!(
            msg.contains("upstream Homebrew bug"),
            "friendly msg should call out upstream bug; got {msg:?}"
        );
        assert!(
            msg.contains("brew untap"),
            "friendly msg should hint at brew untap as a workaround; got {msg:?}"
        );
    }

    #[test]
    fn topo_sort_pattern_matches_on_bundle_install() {
        // Same class of bug; bundle install can hit the same topo path.
        let msg = friendlify(REAL_TOPO_STDERR, "brew bundle install --file=/tmp/x");
        assert!(msg.is_some(), "topo-sort pattern should match on `bundle install`");
    }

    #[test]
    fn please_report_pattern_matches_when_both_substrings_present() {
        let msg = friendlify(REAL_REPORT_STDERR, "brew bundle dump --file=/tmp/x --force")
            .expect("please-report pattern should match real stderr");
        assert!(
            msg.contains("docs.brew.sh/Troubleshooting"),
            "friendly msg should link to brew troubleshooting docs; got {msg:?}"
        );
    }

    // ---- non-matches ----

    #[test]
    fn returns_none_for_generic_install_failure() {
        let stderr = "Error: No available formula with the name \"definitely-not-a-real-pkg\".\n";
        assert!(
            friendlify(stderr, "brew install definitely-not-a-real-pkg").is_none(),
            "unknown-formula errors must fall through to the generic surface"
        );
    }

    #[test]
    fn topo_pattern_does_not_fire_on_non_bundle_command() {
        // Even if the stderr happened to match, the topo pattern is gated to
        // bundle subcommands — we don't want to overreach onto `brew install`
        // stderr that mentions "Topo" for unrelated reasons.
        assert!(
            friendlify(REAL_TOPO_STDERR, "brew install foo").is_none(),
            "topo pattern must not fire on non-bundle commands"
        );
    }

    #[test]
    fn returns_none_when_only_one_topo_substring_present() {
        // "key not found:" without the Topo frame is too generic to claim.
        let stderr = "Error: key not found: \"some/other/thing\"\n";
        assert!(
            friendlify(stderr, "brew bundle dump --file=/tmp/x --force").is_none(),
            "must require both substrings to avoid false positives"
        );
    }

    // ---- edge cases ----

    #[test]
    fn handles_very_long_stderr_without_panic() {
        // Simulate the bounded ring at its 4 KB cap: noise lines + a real
        // match embedded somewhere in the middle.
        let noise = "noise line that is reasonably long and repeats\n".repeat(80);
        let mut stderr = String::new();
        stderr.push_str(&noise);
        stderr.push_str(REAL_TOPO_STDERR);
        stderr.push_str(&noise);

        let msg = friendlify(&stderr, "brew bundle dump --file=/tmp/x --force");
        assert!(
            msg.is_some(),
            "should still find the pattern when sandwiched in noise"
        );
    }

    #[test]
    fn multibyte_stderr_is_safe() {
        // Make sure substring scan doesn't choke on non-ASCII content. The
        // `str::contains` API is char-safe, but pin a regression test anyway.
        let stderr = "ログ: 日本語のエラーメッセージ\n\
                      Error: key not found: \"foo/bar/baz\"\n\
                      Homebrew::Bundle::Brew::Topo crashed\n\
                      終わり\n";
        let msg = friendlify(stderr, "brew bundle dump --file=/tmp/x --force");
        assert!(
            msg.is_some(),
            "multibyte content must not prevent pattern detection"
        );
    }

    #[test]
    fn empty_inputs_return_none() {
        assert!(friendlify("", "").is_none());
        assert!(friendlify("", "brew bundle dump").is_none());
        assert!(friendlify("Error: anything", "").is_none());
    }

    // ---- launchd domain ----

    const REAL_LAUNCHD_STDERR: &str = "Error: Could not find service \"ollama\" in domain for current user (gui/501/16).\nTry running launchctl bootstrap under the right domain, or move the plist to ~/Library/LaunchAgents.\n";

    #[test]
    fn launchd_domain_pattern_matches_on_services() {
        let msg = friendlify(REAL_LAUNCHD_STDERR, "brew services start ollama")
            .expect("launchd pattern should match real services-start stderr");
        assert!(
            msg.contains("launchd") && msg.contains("~/Library/LaunchAgents"),
            "friendly msg should mention launchd and the plist location; got {msg:?}"
        );
    }

    #[test]
    fn launchd_pattern_does_not_fire_on_unrelated_command() {
        // The substring 'Could not find service' alone must not trigger the
        // hint; the gate is command contains services.
        assert!(
            friendlify(REAL_LAUNCHD_STDERR, "brew install ollama").is_none(),
            "launchd pattern must not fire outside services commands"
        );
    }

    #[test]
    fn launchd_pattern_does_not_fire_on_empty_stderr() {
        assert!(
            friendlify("", "brew services start ollama").is_none(),
            "empty stderr must fall through"
        );
    }

}
