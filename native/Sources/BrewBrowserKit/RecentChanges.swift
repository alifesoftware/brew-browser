import Foundation

/// Pure derivation of a "Recent changes" feed over the existing, already-persisted
/// activity log (`ActivityJob`) — NOT a new event store. Each terminal job is
/// classified into a `ChangeKind` by parsing its `label`/`command`, the affected
/// package name(s) are extracted, and the list is returned most-recent-first.
///
/// This is the shared, testable contract that keeps the native shell in parity
/// with the Tauri `recentChanges(jobs)` mapper: identical classification rules,
/// identical past-tense verbs (reusing `ActivityView.displayLabel`), identical
/// inclusion rules, and NO version delta (the activity log records none — see
/// the data-source notes in `Activity.swift`). Stateless `Sendable` value type,
/// mirroring the `CategoryCatalog` service pattern (`Categories.swift`).

/// The package-affecting kinds surfaced in the change feed. `other` covers
/// `brew update` (tap refresh), `brew bundle` (snapshot dump/restore), and any
/// unrecognized label — all excluded from the feed so it stays meaningful.
enum ChangeKind: String, Hashable, Sendable {
    case installed, upgraded, uninstalled, other
}

/// One derived row in the Recent changes feed. `package` is the single affected
/// package, or `nil` for a bulk upgrade (in which case `count` carries the number
/// when the label states it, e.g. "Upgrading 3 packages"; "Upgrading all
/// packages" has no count, so `count` is `nil`). No version delta is carried —
/// the activity log records none and we never fabricate one.
struct RecentChange: Identifiable, Hashable, Sendable {
    /// Stable identity = the originating job's id (one row per job).
    let id: UUID
    let kind: ChangeKind
    let package: String?
    let count: Int?
    /// Epoch seconds, normalized from the job's `startedAt` (native already
    /// stores epoch; Tauri normalizes its ISO string to the same units so both
    /// shells render identical relative times).
    let startedAt: Double
    let status: ActivityJob.JobStatus
}

/// Stateless classifier + feed builder. All methods are pure `static func`s so
/// the logic is trivially testable and identical across call sites.
enum RecentChanges {

    /// Classify a single job's `label`/`command` into a `ChangeKind` and extract
    /// the affected package (single) or bulk count. The package name is read from
    /// the *label* (e.g. "Installing iterm2"), never parsed out of the command —
    /// so command flags like `--force` are ignored. Unknown labels return
    /// `.other` (never crashes, never mis-attributes).
    static func classify(label: String, command: String) -> (kind: ChangeKind, package: String?, count: Int?) {
        // Bulk upgrades first — they share the "Upgrading " prefix but carry no
        // single package name. "Upgrading all packages" → no count; "Upgrading N
        // packages" → parse N.
        if label == "Upgrading all packages" {
            return (.upgraded, nil, nil)
        }
        if let count = bulkUpgradeCount(label) {
            return (.upgraded, nil, count)
        }

        if let pkg = package(after: "Installing ", in: label) {
            return (.installed, pkg, nil)
        }
        if let pkg = package(after: "Upgrading ", in: label) {
            return (.upgraded, pkg, nil)
        }
        if let pkg = package(after: "Uninstalling ", in: label) {
            return (.uninstalled, pkg, nil)
        }

        // "Updating Homebrew" (brew update), "Dumping Brewfile: …" / "Restoring …"
        // (brew bundle), and anything else are not per-package changes.
        return (.other, nil, nil)
    }

    /// Build the most-recent-first change feed from a job history. Excludes
    /// running jobs (a change isn't done until terminal) and `.other` kinds
    /// (update/bundle/unknown). Failed and canceled jobs are RETAINED so the feed
    /// can render them as visually-distinct "attempted" rows rather than silently
    /// dropping them — the caller decides the styling, the contract carries the
    /// `status`. Sorted by `startedAt` descending, stable for equal timestamps.
    static func recentChanges(_ jobs: [ActivityJob]) -> [RecentChange] {
        let changes: [(index: Int, change: RecentChange)] = jobs.enumerated().compactMap { index, job in
            guard job.status != .running else { return nil }
            let (kind, package, count) = classify(label: job.label, command: job.command)
            guard kind != .other else { return nil }
            return (index, RecentChange(
                id: job.id,
                kind: kind,
                package: package,
                count: count,
                startedAt: job.startedAt,
                status: job.status
            ))
        }
        // Stable most-recent-first: sort by startedAt descending, breaking ties
        // by original index so equal timestamps keep their input order.
        return changes
            .sorted { a, b in
                if a.change.startedAt != b.change.startedAt {
                    return a.change.startedAt > b.change.startedAt
                }
                return a.index < b.index
            }
            .map(\.change)
    }

    // MARK: - Private helpers

    /// Extract the package token following a known label prefix, e.g.
    /// `package(after: "Installing ", in: "Installing wget") == "wget"`. The
    /// remainder is the package as the label was emitted; flags never appear in
    /// labels (they live on the command), so no flag-stripping is needed. Returns
    /// nil when the prefix doesn't match or the remainder is empty.
    private static func package(after prefix: String, in label: String) -> String? {
        guard label.hasPrefix(prefix) else { return nil }
        let pkg = String(label.dropFirst(prefix.count))
        return pkg.isEmpty ? nil : pkg
    }

    /// Parse the N from a bulk-upgrade label "Upgrading N packages". Returns nil
    /// when the label isn't that shape (so single-package "Upgrading wget" falls
    /// through to the single-package branch).
    private static func bulkUpgradeCount(_ label: String) -> Int? {
        let prefix = "Upgrading "
        let suffix = " packages"
        guard label.hasPrefix(prefix), label.hasSuffix(suffix) else { return nil }
        let middle = label.dropFirst(prefix.count).dropLast(suffix.count)
        return Int(middle)
    }
}
