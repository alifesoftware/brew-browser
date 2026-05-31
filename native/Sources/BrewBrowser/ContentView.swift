import SwiftUI

/// Root chrome — stock `NavigationSplitView`, no overrides. Apple renders the
/// sidebar, the unified title bar, the toolbar, and all materials. We don't
/// touch the window, tint, transparency, or title bar.
struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $model.selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .badge(model.badge(for: section) ?? 0)  // stock count badge; 0 hides it
                    .tag(section)
            }
            .navigationTitle("brew-browser")
            // Wider sidebar so section labels + count badges never crowd, and
            // there's room for the toolbar's icon+text mode without overflow.
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detail
                // Give the main pane a firm minimum width so dragging the
                // inspector divider takes space from the content down to this
                // floor and then STOPS — instead of collapsing the pane (which
                // the window then grabs as a resize, hiding the inspector).
                // Pairs with .windowResizability(.contentMinSize) on the scene.
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(model.selection.rawValue)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isLoading)

                        Button {
                            // Install new package — wired in full port.
                        } label: {
                            Label("Add", systemImage: "plus")
                        }

                        // Stock SettingsLink opens the native Settings scene.
                        SettingsLink {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                // Search lives on the DETAIL column (the main content area), not
                // the split-view root — so it stays in the content toolbar and
                // doesn't drift over the inspector (and the inspector's boundary
                // divider falls cleanly at the panel edge, not through the
                // toolbar between our icons and the field).
                .searchable(text: $model.globalQuery, placement: .toolbar, prompt: "Search packages")
                .searchSuggestions {
                    ForEach(model.suggestions) { pkg in
                        Label(pkg.name, systemImage: "shippingbox")
                            .searchCompletion(pkg.name)
                    }
                }
                .onSubmit(of: .search) {
                    if let match = model.installed.first(where: {
                        $0.name.caseInsensitiveCompare(model.globalQuery) == .orderedSame
                    }) ?? model.suggestions.first {
                        model.openInLibrary(match)
                    }
                }
                // Package detail — stock right-side inspector, on the detail column.
                .inspector(isPresented: Binding(
                    get: { model.showDetail },
                    // A drag-collapse flips this to false but KEEPS the loaded
                    // package, so re-expanding mid-gesture restores content. The
                    // ⊗ close box calls closeDetail() to actually clear the data.
                    set: { model.showDetail = $0 }
                )) {
                    // The inspector must present a STABLE size contract while the
                    // user drags the divider. Putting .inspectorColumnWidth on an
                    // always-present Group (not on the conditionally-created
                    // PackageDetailView) and letting the content fill the column
                    // stops the hosting view from re-reporting min/max mid-drag.
                    // That re-report otherwise triggers a re-entrant NSWindow
                    // constraint update during -[NSSplitView mouseDown:], which
                    // AppKit aborts (SIGABRT) — or resolves by resizing the
                    // window / hiding the inspector instead of resizing it.
                    //
                    // NOTE: stock `.inspector` dismisses itself when the divider
                    // is dragged below `min` — that's Apple's built-in collapse
                    // behavior, not removable without fighting NSSplitView. We set
                    // a generous `min` (360) so collapsing takes a deliberate hard
                    // drag rather than an accidental nudge; the in-panel close box
                    // (xmark.circle in PackageDetailView) is the intended dismiss.
                    Group {
                        if let pkg = model.detailPackage {
                            PackageDetailView(model: model, pkg: pkg)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .inspectorColumnWidth(min: 360, ideal: 400, max: 560)
                }
        }
        .task {
            if model.installed.isEmpty { await model.loadLibrary() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .dashboard:
            DashboardView(model: model)
        case .library:
            LibraryView(model: model)
        default:
            PlaceholderView(section: model.selection)
        }
    }
}

/// Installed formulae — a stock `List` with the system `.searchable` field.
/// No floating header, no glass, no custom row chrome.
struct LibraryView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.isLoading && model.installed.isEmpty {
                ProgressView("Reading your Homebrew install…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = model.loadError {
                ContentUnavailableView(
                    "Couldn't load packages",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else if model.filtered.isEmpty {
                ContentUnavailableView.search(text: model.query)
            } else {
                List(model.filtered) { pkg in
                    Button {
                        model.openDetail(pkg)
                    } label: {
                        LabeledContent {
                            Text(pkg.version)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } label: {
                            Label(pkg.name, systemImage: "shippingbox")
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $model.query, prompt: "Filter formulae")
    }
}

struct PlaceholderView: View {
    let section: Section

    var body: some View {
        ContentUnavailableView(
            section.rawValue,
            systemImage: section.symbol,
            description: Text("Wired in the full port. The spike proves Dashboard + Library end-to-end.")
        )
    }
}
