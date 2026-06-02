import SwiftUI

/// Discover — browse the full Homebrew catalog (available packages, not just
/// installed). Same stock `Table` + selection→inspector pattern as Library,
/// with a category `Picker` filter bar and async app-icon resolution (Appcasks
/// → Google favicon → SF Symbol). Reuses `globalQuery` as the single search
/// field (no second `.searchable` — see LibraryView for why).
struct DiscoverView: View {
    @Bindable var model: AppModel

    @State private var selectedID: DiscoverRow.ID?

    var body: some View {
        Group {
            if model.catalogLoading && model.catalog.isEmpty {
                ProgressView("Loading the Homebrew catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    filterBar
                    Divider()
                    table
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task { await model.loadCatalog() }
        .onChange(of: model.showDetail) { _, shown in
            if !shown { selectedID = nil }
        }
    }

    // Category Picker, centered (matches Library's centered segmented filter).
    private var filterBar: some View {
        Picker("Category", selection: $model.discoverCategory) {
            Text("All Categories").tag(String?.none)
            ForEach(model.categoryList, id: \.slug) { cat in
                Text(cat.label).tag(String?.some(cat.slug))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var table: some View {
        let rows = model.sortedDiscoverRows
        if rows.isEmpty {
            if model.catalog.isEmpty {
                ContentUnavailableView("Catalog unavailable",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("The bundled package catalog couldn't be loaded."))
            } else if !model.globalQuery.isEmpty {
                ContentUnavailableView.search(text: model.globalQuery)
            } else {
                ContentUnavailableView("No packages",
                                       systemImage: "sparkles.rectangle.stack",
                                       description: Text("Nothing in this category."))
            }
        } else {
            // AI-gated Description column → two static column sets (a conditional
            // TableColumn inside one builder destabilizes NSTableColumn and
            // crashes on layout — same lesson as Library).
            if model.settings.aiFeaturesVisible {
                discoverTable(rows, showDescription: true)
            } else {
                discoverTable(rows, showDescription: false)
            }
        }
    }

    @ViewBuilder
    private func discoverTable(_ rows: [DiscoverRow], showDescription: Bool) -> some View {
        if showDescription {
            Table(rows, selection: $selectedID, sortOrder: $model.discoverSort) {
                TableColumn("Name", value: \.name) { iconNameCell($0) }.width(min: 160, ideal: 220)
                TableColumn("Description", value: \.summary) { r in
                    Text(r.summary).foregroundStyle(.secondary).lineLimit(1)
                }.width(min: 160, ideal: 300)
                TableColumn("Version", value: \.version) { r in
                    Text(r.version).foregroundStyle(.secondary).monospacedDigit()
                }.width(min: 70, ideal: 100)
                TableColumn("Type", value: \.kind.rawValue) { KindPill(kind: $0.kind) }.width(min: 64, ideal: 80)
                TableColumn("Installed", value: \.installedRank) { installedCell($0) }.width(min: 64, ideal: 80)
            }
            .onChange(of: selectedID, openSelected)
        } else {
            Table(rows, selection: $selectedID, sortOrder: $model.discoverSort) {
                TableColumn("Name", value: \.name) { iconNameCell($0) }.width(min: 200, ideal: 280)
                TableColumn("Version", value: \.version) { r in
                    Text(r.version).foregroundStyle(.secondary).monospacedDigit()
                }.width(min: 70, ideal: 100)
                TableColumn("Type", value: \.kind.rawValue) { KindPill(kind: $0.kind) }.width(min: 64, ideal: 80)
                TableColumn("Installed", value: \.installedRank) { installedCell($0) }.width(min: 64, ideal: 80)
            }
            .onChange(of: selectedID, openSelected)
        }
    }

    // Icon + name cell. Icon resolves async into model.iconCache (Appcasks →
    // Google favicon); formulae + unresolved casks show an SF Symbol.
    @ViewBuilder
    private func iconNameCell(_ row: DiscoverRow) -> some View {
        HStack(spacing: 8) {
            PackageIcon(model: model, token: row.token, kind: row.kind, homepage: row.homepage)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.token)
                if !row.friendlyName.isEmpty {
                    Text(row.friendlyName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func installedCell(_ row: DiscoverRow) -> some View {
        if row.isInstalled {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Installed")
        }
    }

    private func openSelected() {
        guard let id = selectedID,
              let row = model.sortedDiscoverRows.first(where: { $0.id == id }) else { return }
        // Reuse the shared detail inspector — wrap the catalog row as a package.
        model.openDetail(InstalledPackage(name: row.token, version: row.version, kind: row.kind))
    }
}

/// A small app icon for any list row (Discover, Library, …): the resolved
/// cached image when present, else an SF Symbol. Triggers async resolution on
/// appear (casks only; formulae are CLI tools → terminal glyph). Shared so every
/// list shows the same real icons. `homepage` is only needed for the favicon
/// fallback; installed casks usually resolve via Appcasks token-only, so passing
/// "" is fine.
struct PackageIcon: View {
    @Bindable var model: AppModel
    let token: String
    let kind: InstalledPackage.Kind
    var homepage: String = ""
    var size: CGFloat = 20

    var body: some View {
        Group {
            if kind == .cask, let url = model.iconCache[token],
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                Image(systemName: kind == .cask ? "app.dashed" : "terminal")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: token) {
            await model.resolveIcon(token: token, kind: kind, homepage: homepage)
        }
    }
}

#if DEBUG
#Preview("Discover") {
    DiscoverView(model: .preview())
        .frame(width: 820, height: 560)
}
#endif
