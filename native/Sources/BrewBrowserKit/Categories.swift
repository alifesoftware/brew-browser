import Foundation

/// Loads the bundled `categories.json` (package→category-slug map) and computes
/// the "Top categories in your library" breakdown from installed packages —
/// the real data behind the Dashboard donut, same source as the Tauri app.
struct CategoryBreakdown: Identifiable, Hashable, Sendable {
    var id: String { slug }
    let slug: String
    let label: String
    let count: Int
    let fraction: Double
    /// SF Symbol name for the category, read straight from `categories.json`'s
    /// `iconSF` field (chosen once in `tools/categorize/categorize.py`). No
    /// per-icon mapping in UI code — the data decides the glyph.
    var icon: String = "questionmark.circle"
}

/// One Discover category tile: glyph + label + the number of catalog packages in
/// the category. Backs the Discover browse grid (mirrors the Tauri
/// `CategoryTile` in `src/lib/stores/categories.svelte.ts`).
struct CategoryTile: Identifiable, Hashable, Sendable {
    var id: String { slug }
    let slug: String
    let label: String
    /// SF Symbol from `categories.json` `iconSF` (data-driven, no UI mapping).
    let icon: String
    let count: Int
}

/// One co-occurrence sub-group within a selected category (feature #6).
///
/// IMPORTANT — this is NOT a true taxonomy tree. `categories.json` is strictly
/// flat (no nested/sub-category field exists, and the offline categorizer emits
/// a fixed single level). The only genuine second-level signal already in the
/// data is multi-label membership: within category X, members are grouped by
/// their OTHER co-assigned category slug, plus a sentinel `"__general__"` bucket for
/// members carrying only X. Labels say "<X> + <Y>" / "General <X>" so the UI
/// never implies a hierarchy the data doesn't have.
struct CategorySubgroup: Identifiable, Hashable, Sendable {
    var id: String { key }
    /// Co-occurring category slug, or the sentinel `"__general__"` for solo members.
    let key: String
    /// "<Selected Label> + <Other Label>", or "General <Selected Label>".
    let label: String
    /// Member `(token, kind)` pairs, deduped within this sub-group, sorted by
    /// token (case-insensitive) for a deterministic, parity-identical order.
    let members: [SubgroupMember]
    var count: Int { members.count }
}

/// A sub-group member: a catalog token + its kind, matching the Tauri
/// `tokensInCategory` member shape (`{ name, kind }`) so membership is
/// byte-identical across the two shells.
struct SubgroupMember: Hashable, Sendable {
    let token: String
    let kind: InstalledPackage.Kind
}

/// Sentinel sub-group key for members that carry ONLY the selected category.
let categorySubgroupGeneralKey = "__general__"

struct CategoryCatalog: Sendable {
    /// slug → display label
    private let labels: [String: String]
    /// slug → SF Symbol name (from `categories.json` `iconSF`)
    private let sfIcons: [String: String]
    /// package name → [slug]
    private let formulae: [String: [String]]
    private let casks: [String: [String]]

    /// Decode the bundled JSON. Returns nil if the resource is missing or
    /// malformed (the Dashboard then just hides the categories card).
    static func loadBundled() -> CategoryCatalog? {
        guard let url = Bundle.module.url(forResource: "categories", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return parse(data: data)
    }

    /// Parse a `categories.json` blob — bundled OR live-fetched from the
    /// `…/enrichment/categories.json` endpoint — into a catalog.
    static func parse(data: Data) -> CategoryCatalog? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var labels: [String: String] = [:]
        var sfIcons: [String: String] = [:]
        if let cats = root["categories"] as? [String: Any] {
            for (slug, v) in cats {
                guard let obj = v as? [String: Any] else { continue }
                if let label = obj["label"] as? String { labels[slug] = label }
                if let sf = obj["iconSF"] as? String { sfIcons[slug] = sf }
            }
        }
        let formulae = (root["formulae"] as? [String: [String]]) ?? [:]
        let casks = (root["casks"] as? [String: [String]]) ?? [:]
        return CategoryCatalog(labels: labels, sfIcons: sfIcons, formulae: formulae, casks: casks)
    }

    /// Category slugs for an installed package (formula first, then cask map).
    private func slugs(for name: String, kind: InstalledPackage.Kind) -> [String] {
        let map = kind == .cask ? casks : formulae
        return map[name] ?? []
    }

    /// Display labels for a single package's categories (for the detail panel
    /// pills), excluding the "uncategorized" bucket.
    func categoryLabels(for name: String, kind: InstalledPackage.Kind) -> [String] {
        slugs(for: name, kind: kind)
            .filter { $0 != "uncategorized" }
            .map { labels[$0] ?? $0.capitalized }
    }

    /// All known categories as (slug, label), alphabetised by label — powers the
    /// Discover category Picker. Excludes the "uncategorized" bucket.
    func allCategories() -> [(slug: String, label: String)] {
        labels
            .filter { $0.key != "uncategorized" }
            .map { (slug: $0.key, label: $0.value) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// True if a package (by token + kind) belongs to the given category slug —
    /// the Discover category filter predicate.
    func isMember(token: String, kind: InstalledPackage.Kind, slug: String) -> Bool {
        slugs(for: token, kind: kind).contains(slug)
    }

    /// Category tiles for the Discover browse grid: every known category with its
    /// glyph + the count of catalog packages (formulae + casks) in it, sorted by
    /// descending count. Mirrors the Tauri `categories.tiles` derivation
    /// (`src/lib/stores/categories.svelte.ts:62-81`); `uncategorized` is excluded
    /// (the Tauri grid sinks it to last, native simply omits the noise bucket).
    func tiles() -> [CategoryTile] {
        var counts: [String: Int] = [:]
        for cats in formulae.values { for c in cats { counts[c, default: 0] += 1 } }
        for cats in casks.values { for c in cats { counts[c, default: 0] += 1 } }
        return labels
            .filter { $0.key != "uncategorized" }
            .map { slug, label in
                CategoryTile(slug: slug, label: label,
                             icon: sfIcons[slug] ?? "questionmark.circle",
                             count: counts[slug] ?? 0)
            }
            .sorted { $0.count > $1.count }
    }

    /// All `(token, kind)` members of a category slug, sorted by token
    /// (case-insensitive). Mirrors the Tauri `tokensInCategory` (member shape
    /// `{ name, kind }`, same ordering). Casks first/formulae order doesn't
    /// matter — the final sort is by token — but matching the value set is what
    /// keeps the two shells in parity. Native is macOS-only, so casks are always
    /// included (no `isLinux` gate; the Tauri side applies that gate).
    func membersInCategory(_ slug: String) -> [SubgroupMember] {
        var out: [SubgroupMember] = []
        for (token, cats) in casks where cats.contains(slug) {
            out.append(SubgroupMember(token: token, kind: .cask))
        }
        for (token, cats) in formulae where cats.contains(slug) {
            out.append(SubgroupMember(token: token, kind: .formula))
        }
        out.sort { $0.token.localizedCaseInsensitiveCompare($1.token) == .orderedAscending }
        return out
    }

    /// Whether a member belongs to the given sub-group `key` WITHIN `slug` — the
    /// drill-down predicate that mirrors ``subgroups(in:)`` bucketing exactly so
    /// a drilled-in list matches the sub-group's member count. `"__general__"` means
    /// the member carries no OTHER real category (uncategorized doesn't count);
    /// any other key means the member is also assigned that category.
    func memberInSubgroup(token: String, kind: InstalledPackage.Kind,
                          slug: String, subgroupKey: String) -> Bool {
        let cats = slugs(for: token, kind: kind)
        guard cats.contains(slug) else { return false }
        let others = cats.filter { $0 != slug && $0 != "uncategorized" }
        if subgroupKey == categorySubgroupGeneralKey { return others.isEmpty }
        return others.contains(subgroupKey)
    }

    /// Co-occurrence sub-groups for a single selected category (feature #6).
    ///
    /// Given category `slug`, every member of that category is bucketed by each
    /// of its OTHER category slugs; a member carrying only `slug` (no other real
    /// category) lands in the sentinel `"__general__"` bucket. A member with N other
    /// categories appears under each of those N sub-groups (deduped WITHIN a
    /// bucket, NOT across — by design). `"uncategorized"` is never a co-occurring
    /// bucket: it's excluded exactly as `tiles()`/`allCategories()` exclude it,
    /// so a member whose only other slug is `uncategorized` is treated as solo.
    ///
    /// Ordering: descending member count, tie-break by ascending slug, with the
    /// `"__general__"` bucket PINNED LAST. (Parity decision — both shells pin
    /// `__general__` last and use the same tie-break.) Member lists inside each
    /// bucket are token-sorted via ``membersInCategory``.
    ///
    /// Pure: derives solely from the in-memory `categories.json` maps — no
    /// commands, no subprocess, no refetch. Returns `[]` for an unknown slug.
    func subgroups(in slug: String) -> [CategorySubgroup] {
        let selectedLabel = labels[slug] ?? slug.capitalized
        var buckets: [String: [SubgroupMember]] = [:]

        for member in membersInCategory(slug) {
            let others = slugs(for: member.token, kind: member.kind)
                .filter { $0 != slug && $0 != "uncategorized" }
            if others.isEmpty {
                buckets[categorySubgroupGeneralKey, default: []].append(member)
            } else {
                // Dedup within a bucket: a member can't legitimately carry the
                // same other-slug twice, but guard anyway so counts are exact.
                for other in Set(others) {
                    buckets[other, default: []].append(member)
                }
            }
        }

        let groups: [CategorySubgroup] = buckets.map { key, members in
            let sorted = members.sorted {
                $0.token.localizedCaseInsensitiveCompare($1.token) == .orderedAscending
            }
            let label: String
            if key == categorySubgroupGeneralKey {
                label = "General \(selectedLabel)"
            } else {
                label = "\(selectedLabel) + \(labels[key] ?? key.capitalized)"
            }
            return CategorySubgroup(key: key, label: label, members: sorted)
        }

        return groups.sorted { a, b in
            // Pin the sentinel "__general__" bucket last.
            if a.key == categorySubgroupGeneralKey { return false }
            if b.key == categorySubgroupGeneralKey { return true }
            if a.count != b.count { return a.count > b.count }
            return a.key < b.key
        }
    }

    /// Top-N category breakdown across the installed set. Each package
    /// contributes 1 to each of its categories (multi-membership), matching the
    /// Tauri model. "uncategorized" is folded into an "Other" bucket along with
    /// the long tail beyond `top`.
    func breakdown(installed: [InstalledPackage], top: Int = 8) -> [CategoryBreakdown] {
        var counts: [String: Int] = [:]
        for pkg in installed {
            for slug in slugs(for: pkg.name, kind: pkg.kind) {
                counts[slug, default: 0] += 1
            }
        }
        let uncategorized = counts.removeValue(forKey: "uncategorized") ?? 0
        let totalMemberships = max(1, counts.values.reduce(0, +) + uncategorized)

        let ranked = counts.sorted { $0.value > $1.value }
        var result: [CategoryBreakdown] = []
        for (slug, count) in ranked.prefix(top) {
            result.append(CategoryBreakdown(
                slug: slug,
                label: labels[slug] ?? slug.capitalized,
                count: count,
                fraction: Double(count) / Double(totalMemberships),
                icon: sfIcons[slug] ?? "questionmark.circle"
            ))
        }
        let tail = ranked.dropFirst(top).reduce(0) { $0 + $1.value } + uncategorized
        if tail > 0 {
            result.append(CategoryBreakdown(
                slug: "other",
                label: "Other",
                count: tail,
                fraction: Double(tail) / Double(totalMemberships),
                icon: "questionmark.circle"
            ))
        }
        return result
    }
}
