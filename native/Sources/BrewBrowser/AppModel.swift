import SwiftUI

/// The sidebar sections, mirroring the shipped app's navigation. Spike wires up
/// Library for real; the rest are placeholders to prove the NavigationSplitView
/// chrome and selection model.
enum Section: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case library   = "Library"
    case discover  = "Discover"
    case trending  = "Trending"
    case snapshots = "Snapshots"
    case services  = "Services"
    case activity  = "Activity"

    var id: String { rawValue }

    /// SF Symbol for the sidebar row — all system symbols, no custom assets.
    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .library:   return "books.vertical"
        case .discover:  return "sparkles.rectangle.stack"
        case .trending:  return "chart.line.uptrend.xyaxis"
        case .snapshots: return "camera"
        case .services:  return "gearshape.2"
        case .activity:  return "list.bullet.rectangle"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var selection: Section = .dashboard
    var installed: [InstalledPackage] = []
    var isLoading = false
    var loadError: String?

    /// Live filter text for the Library search field (`.searchable`).
    var query: String = ""

    /// Global toolbar search text (the centered Safari-style field).
    var globalQuery: String = ""

    /// When set from the Dashboard, Library shows only outdated packages.
    var libraryOutdatedOnly = false

    /// Case-insensitive name filter, optionally restricted to outdated.
    var filtered: [InstalledPackage] {
        var base = installed
        if libraryOutdatedOnly {
            let names = Set(outdated.map(\.name))
            base = base.filter { names.contains($0.name) }
        }
        guard !query.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Type-ahead suggestions for the toolbar search — top installed matches.
    var suggestions: [InstalledPackage] {
        let q = globalQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(
            installed
                .filter { $0.name.localizedCaseInsensitiveContains(q) }
                .prefix(8)
        )
    }

    /// Commit a search selection: jump to Library, pre-filtered to that name.
    func openInLibrary(_ pkg: InstalledPackage) {
        query = pkg.name
        libraryOutdatedOnly = false
        selection = .library
        globalQuery = ""
    }

    /// Open the full Library (cleared filters). Used by the "installed" stat.
    func openLibrary() {
        query = ""
        libraryOutdatedOnly = false
        selection = .library
    }

    /// Open Library filtered to outdated packages. Used by the Updates stat/card.
    func openOutdatedInLibrary() {
        query = ""
        libraryOutdatedOnly = true
        selection = .library
    }

    // ---- Dashboard stats (all from real brew data) ----
    var formulaCount = 0
    var caskCount = 0
    var leavesCount = 0
    var onRequestCount = 0
    var pinnedCount = 0
    var outdatedCount = 0
    var outdated: [OutdatedPackage] = []
    var storage: [StorageItem] = []
    var brewVersion = "—"
    var brewPrefix = "/opt/homebrew"
    var categories: [CategoryBreakdown] = []
    var runningServices = 0
    var dashboardLoaded = false

    // ---- Package detail (inspector) ----
    /// The package whose detail is loaded. This is the DATA, decoupled from
    /// presentation: it's only set by `openDetail` and only cleared by
    /// `closeDetail` (the ⊗ close box). A drag-collapse of the inspector must
    /// NOT clear it, or re-expanding within the same gesture shows an empty pane.
    var detailPackage: InstalledPackage?
    /// Inspector PRESENTATION flag — what the `.inspector(isPresented:)` binding
    /// reads/writes. A divider drag past `min` flips this to false (collapse)
    /// while `detailPackage` survives, so the panel can re-expand with content.
    var showDetail = false
    var detailInfo: PackageInfo?
    var detailEnrichment: EnrichmentEntry?
    var detailCategories: [String] = []        // category labels for this package
    var detailLoading = false
    var detailError: String?
    /// Streaming action state (upgrade/uninstall/install) for the footer.
    var actionRunning = false
    var actionLabel: String?

    // ---- Vulnerabilities (Security card) ----
    var detailVulns: [VulnFinding] = []
    var detailVulnsScanned = false
    var detailVulnsLoading = false
    var brewVulnsInstalled = false

    // ---- Install trend ----
    var detailTrend: TrendingHistorySeries?

    // ---- GitHub ----
    var detailRepoStats: RepoStats?
    var detailStarred: Bool?
    var githubStatus: GithubStatus?

    private let catalog = CategoryCatalog.loadBundled()
    private let enrichment = EnrichmentCatalog.loadBundled()
    let settings = AppSettings.shared
    private let vulns = VulnsService()
    private let trendingHistory = TrendingHistoryService()
    private let githubService = GitHubService()

    init() {}

    /// Count badge for a sidebar section (nil = no badge). Library shows the
    /// outdated count; Services shows running services.
    func badge(for section: Section) -> Int? {
        switch section {
        case .library:  return outdatedCount > 0 ? outdatedCount : nil
        case .services: return runningServices > 0 ? runningServices : nil
        default:        return nil
        }
    }

    /// Dependencies = installed formulae that weren't explicitly requested.
    var dependencyCount: Int { max(0, formulaCount - leavesCount) }
    var totalPackages: Int { formulaCount + caskCount }

    /// First 5 outdated packages for the Dashboard preview list.
    var outdatedPreview: [OutdatedPackage] { Array(outdated.prefix(5)) }

    /// Total bytes across all storage categories.
    var storageTotalBytes: Int64 { storage.reduce(0) { $0 + $1.bytes } }

    private let brew = BrewService()

    func loadLibrary() async {
        isLoading = true
        loadError = nil
        do {
            installed = try await brew.listInstalledFormulae()
            formulaCount = installed.count
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Load all Dashboard stats. Reuses the Library load for the formula count
    /// (and triggers it if it hasn't run), then fans out the cheap counts.
    func loadDashboard() async {
        if installed.isEmpty { await loadLibrary() } else { formulaCount = installed.count }
        async let casks = try? brew.countCasks()
        async let leaves = try? brew.countLeaves()
        async let onRequest = try? brew.countOnRequest()
        async let pinned = try? brew.countPinned()
        async let outdatedList = try? brew.outdatedPackages()
        async let storageList = brew.storageBreakdown()
        async let ver = brew.version()
        async let pfx = brew.prefix()
        async let services = brew.countRunningServices()

        caskCount = await casks ?? 0
        leavesCount = await leaves ?? 0
        onRequestCount = await onRequest ?? 0
        pinnedCount = await pinned ?? 0
        outdated = await outdatedList ?? []
        outdatedCount = outdated.count
        storage = await storageList
        brewVersion = await ver
        brewPrefix = await pfx
        categories = catalog?.breakdown(installed: installed) ?? []
        runningServices = await services
        dashboardLoaded = true
    }

    /// Toolbar Refresh — reload whichever surface is showing.
    func refresh() async {
        await loadLibrary()
        dashboardLoaded = false
        await loadDashboard()
    }

    // MARK: - Package detail

    /// Open the inspector for a package and load its full detail.
    func openDetail(_ pkg: InstalledPackage) {
        detailPackage = pkg
        showDetail = true
        Task { await loadDetail(pkg) }
    }

    func closeDetail() {
        showDetail = false
        detailPackage = nil
        detailInfo = nil
        detailEnrichment = nil
        detailCategories = []
        detailVulns = []
        detailVulnsScanned = false
        detailTrend = nil
        detailRepoStats = nil
        detailStarred = nil
        detailError = nil
    }

    /// Load `brew info` + bundled enrichment/categories for the package, then
    /// kick off the opt-in network sections (trend, github) per settings gates.
    func loadDetail(_ pkg: InstalledPackage) async {
        detailLoading = true
        detailError = nil
        detailInfo = nil
        detailVulns = []
        detailVulnsScanned = false
        detailTrend = nil
        detailRepoStats = nil
        detailStarred = nil

        // Bundled, synchronous-ish lookups first (instant).
        detailEnrichment = settings.aiFeaturesVisible ? enrichment?.entry(for: pkg.name) : nil
        detailCategories = catalog?.categoryLabels(for: pkg.name, kind: pkg.kind) ?? []

        do {
            let info = try await brew.info(name: pkg.name, kind: pkg.kind)
            // Guard against a stale load if the user clicked another package.
            guard detailPackage?.id == pkg.id else { return }
            detailInfo = info
        } catch {
            guard detailPackage?.id == pkg.id else { return }
            detailError = error.localizedDescription
        }
        detailLoading = false

        // Opt-in network sections — fire-and-forget, gated by settings.
        if settings.enhancedTrendingAllowed {
            Task { await loadTrend(pkg) }
        }
        if settings.githubAllowed, let hp = detailInfo?.homepage {
            Task { await loadGitHub(homepage: hp, pkgId: pkg.id) }
        }
        // Probe brew-vulns availability so the Security card shows the right CTA.
        if settings.vulnerabilityScanningAllowed {
            let installed = await vulns.isBrewVulnsInstalled()
            guard detailPackage?.id == pkg.id else { return }
            brewVulnsInstalled = installed
        }
    }

    func loadTrend(_ pkg: InstalledPackage) async {
        let series = await trendingHistory.series(name: pkg.name, isCask: pkg.kind == .cask)
        guard detailPackage?.id == pkg.id else { return }
        detailTrend = series
    }

    func loadGitHub(homepage: String, pkgId: String) async {
        let stats = try? await githubService.repoStats(homepage: homepage)
        guard detailPackage?.id == pkgId else { return }
        detailRepoStats = stats
        let status = await githubService.status()
        if status.signedIn {
            let starred = try? await githubService.isStarred(homepage: homepage)
            guard detailPackage?.id == pkgId else { return }
            detailStarred = starred
        }
    }

    /// Run a `brew vulns` scan for the detail package (Security card "Check now").
    func scanDetailVulns() async {
        guard let pkg = detailPackage else { return }
        detailVulnsLoading = true
        let findings = (try? await vulns.scanOne(name: pkg.name, isCask: pkg.kind == .cask)) ?? []
        guard detailPackage?.id == pkg.id else { return }
        detailVulns = findings
        detailVulnsScanned = true
        detailVulnsLoading = false
    }

    // MARK: - Detail actions

    func upgradeDetail() async {
        guard let pkg = detailPackage else { return }
        await runAction("Upgrading \(pkg.name)") { try await self.brew.upgrade(pkg.name) }
    }

    func uninstallDetail() async {
        guard let pkg = detailPackage else { return }
        await runAction("Uninstalling \(pkg.name)") {
            try await self.brew.uninstall(pkg.name, kind: pkg.kind)
        }
        closeDetail()
    }

    private func runAction(_ label: String, _ work: @escaping () async throws -> Void) async {
        actionRunning = true
        actionLabel = label
        do { try await work() } catch { detailError = error.localizedDescription }
        actionRunning = false
        actionLabel = nil
        // Refresh installed/outdated state after a mutation.
        await refresh()
    }
}
