/**
 * Recent changes — a PURE DERIVATION over the existing activity log.
 *
 * There is no separate "change" event store: every package action already
 * records an {@link ActivityJob} (label + command + startedAt + status) in
 * `activity.svelte.ts`'s localStorage mirror. This module classifies each
 * terminal job into a {@link RecentChange} (action kind + package + timestamp
 * + outcome) so the Dashboard can show a most-recent-first change feed without
 * any new data, subprocess, or persisted event store.
 *
 * PARITY: the native (Swift) build implements the IDENTICAL classifier over
 * its own UserDefaults-persisted job history. Both shells MUST agree on:
 *   1. the label/command prefix classification rules,
 *   2. the past-tense verb mapping (already in native ActivityView.displayLabel:
 *      Installing→Installed, Upgrading→Upgraded, Uninstalling→Uninstalled),
 *   3. the inclusion rule (package-affecting kinds only; running excluded;
 *      succeeded/failed/canceled all kept, with status carried for the UI),
 *   4. most-recent-first ordering with a stable tiebreak,
 *   5. NO version delta — neither shell fabricates one (the activity log
 *      records no structured old→new version; see KNOWN BLOCKERS in the
 *      feature spec).
 *
 * The timestamp is normalized to epoch milliseconds so both shells render
 * identical relative times: Tauri's `startedAt` is an ISO-8601 string, native's
 * is a Double of epoch seconds. {@link normalizeStartedAt} accepts both.
 */

import type { ActivityJob, ChangeKind, RecentChange } from "$lib/types";

/** Default number of changes surfaced on the Dashboard card. */
export const RECENT_CHANGES_LIMIT = 6;

/**
 * Classify a single job's label/command into a change kind + affected package.
 *
 * Classification keys off the LABEL prefix (the canonical human form produced
 * at every `startJob` call site) and falls back to the command. The package
 * name is read from the LABEL, never parsed out of the command, so install
 * flags (e.g. `brew install iterm2 --force`) never leak into the name.
 *
 * Known label forms (see feature spec data_source):
 *   "Installing X"           / "brew install …"   -> installed,   package X
 *   "Upgrading X"            / "brew upgrade X"    -> upgraded,    package X
 *   "Upgrading N packages"   / "Upgrading all …"   -> upgraded (bulk, count N, package null)
 *   "Uninstalling X"         / "brew uninstall …"  -> uninstalled, package X
 *   "Updating Homebrew taps" / "brew update"        -> other (excluded: not a package change)
 *   "Dumping Brewfile…" / "Restoring …" / "brew bundle …" -> other (excluded)
 *   anything else (future label drift)             -> other (skipped, never crashes)
 */
export function classify(
  label: string,
  command: string,
): { kind: ChangeKind; package: string | null; count: number | null } {
  const l = label.trim();

  // Bulk upgrade — no per-package names are available, so carry a count and a
  // null package rather than fabricating individual names. Checked BEFORE the
  // single-package "Upgrading X" branch because "Upgrading 3 packages" and
  // "Upgrading all packages" both start with "Upgrading ".
  const bulkMatch = l.match(/^Upgrading (\d+) packages?$/);
  if (bulkMatch) {
    return { kind: "upgraded", package: null, count: Number(bulkMatch[1]) };
  }
  if (/^Upgrading all packages$/.test(l)) {
    // "all" — count is unknown at job-start time; null count, null package.
    return { kind: "upgraded", package: null, count: null };
  }

  if (l.startsWith("Installing ")) {
    return { kind: "installed", package: extractName(l, "Installing "), count: null };
  }
  if (l.startsWith("Upgrading ")) {
    return { kind: "upgraded", package: extractName(l, "Upgrading "), count: null };
  }
  if (l.startsWith("Uninstalling ")) {
    return { kind: "uninstalled", package: extractName(l, "Uninstalling "), count: null };
  }

  // Everything else — tap refresh ("Updating Homebrew taps"), Brewfile
  // dump/restore, or any future label that doesn't match a known prefix.
  // Not a per-package change; excluded from the feed. `command` is unused for
  // classification today but kept in the signature for parity with native and
  // to leave room for a command-only fallback without an API change.
  void command;
  return { kind: "other", package: null, count: null };
}

/**
 * Pull the package name out of a label by stripping a known verb prefix.
 * Reads ONLY the label (e.g. "Installing iterm2"), so command-line flags
 * never appear in the name. Returns null for an empty remainder.
 */
function extractName(label: string, prefix: string): string | null {
  const rest = label.slice(prefix.length).trim();
  return rest.length > 0 ? rest : null;
}

/**
 * Normalize a job `startedAt` to epoch milliseconds.
 *
 * Tauri persists ISO-8601 strings; native persists epoch SECONDS as a number.
 * Accepting both keeps the derived contract identical across shells. An
 * unparseable value yields 0 so it sorts to the end rather than throwing.
 */
export function normalizeStartedAt(startedAt: string | number): number {
  if (typeof startedAt === "number") {
    // Native shape: epoch seconds → ms. (Defensive: a value already in ms
    // would be absurdly far in the future as seconds, but we never emit ms
    // here — Tauri uses ISO strings — so a plain ×1000 is correct.)
    return Number.isFinite(startedAt) ? startedAt * 1000 : 0;
  }
  const ms = Date.parse(startedAt);
  return Number.isNaN(ms) ? 0 : ms;
}

/**
 * Derive the recent-changes feed from the full job history.
 *
 * - Excludes `running` jobs — a change isn't a change until the job is
 *   terminal. Keeps succeeded/failed/canceled and carries `status` so the UI
 *   can distinguish a completed change from an attempted/failed one.
 * - Excludes `other` kinds (tap update / Brewfile bundle) — not package
 *   changes.
 * - Sorts most-recent-first by normalized timestamp, with a stable tiebreak on
 *   the input order (jobs are unshifted newest-first at `startJob`, so for
 *   equal timestamps the earlier array index is the more recent job).
 * - Carries NO version delta.
 *
 * @param limit cap the result length (default {@link RECENT_CHANGES_LIMIT});
 *   pass `Infinity` for the full feed.
 */
export function recentChanges(
  jobs: readonly ActivityJob[],
  limit: number = RECENT_CHANGES_LIMIT,
): RecentChange[] {
  const out: Array<RecentChange & { _idx: number }> = [];

  for (let i = 0; i < jobs.length; i++) {
    const job = jobs[i];
    if (job.status === "running") continue;

    const { kind, package: pkg, count } = classify(job.label, job.command);
    if (kind === "other") continue;

    out.push({
      jobId: job.jobId,
      kind,
      package: pkg,
      count,
      timestamp: normalizeStartedAt(job.startedAt),
      status: job.status,
      _idx: i,
    });
  }

  out.sort((a, b) => {
    if (b.timestamp !== a.timestamp) return b.timestamp - a.timestamp;
    // Equal timestamps: preserve input order (smaller index = newer).
    return a._idx - b._idx;
  });

  const capped = Number.isFinite(limit) ? out.slice(0, limit) : out;
  // Drop the internal sort key from the public contract.
  return capped.map(({ _idx, ...rest }) => rest);
}

/**
 * Past-tense verb for a change kind. Mirrors native ActivityView.displayLabel
 * exactly (Installing→Installed, Upgrading→Upgraded, Uninstalling→Uninstalled)
 * so both shells render identical verbs.
 */
export function changeVerb(kind: ChangeKind): string {
  switch (kind) {
    case "installed":
      return "Installed";
    case "upgraded":
      return "Upgraded";
    case "uninstalled":
      return "Uninstalled";
    case "other":
      return "Changed";
  }
}

/**
 * Human summary of a single change's subject — the package name, or a bulk
 * descriptor when no per-package name is available.
 *   single:        "wget"
 *   bulk w/ count: "3 packages"
 *   bulk no count: "all packages"
 */
export function changeSubject(change: RecentChange): string {
  if (change.package) return change.package;
  if (change.count !== null) {
    return `${change.count} package${change.count === 1 ? "" : "s"}`;
  }
  return "all packages";
}
