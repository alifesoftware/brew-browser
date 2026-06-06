import SwiftUI
import AppKit
import BrewBrowserKit

@main
struct BrewBrowserApp: App {
    /// When launched as a bare SPM binary (Xcode ⌘R uses the DerivedData
    /// executable, which has no Info.plist), macOS treats the process as a
    /// background/accessory app — the window never comes forward and there's no
    /// Dock icon or menu bar. Forcing `.regular` + activating makes it a normal
    /// foreground app. Harmless when run from the real `.app` bundle (already
    /// `.regular`); this just makes Xcode Run + the debugger usable directly.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The shared app model, owned at the scene root so the scene-level
    /// `.commands` keyboard shortcuts and `ContentView`'s views act on one
    /// instance. (SwiftUI's stock pattern for shared scene + command state.)
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowStyle(.automatic)
        // Native macOS toolbar style — the unified title bar that hosts the
        // Liquid Glass toolbar buttons.
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 720)
        // Keep a coherent minimum window size (sidebar + main-pane min +
        // inspector min) while staying freely resizable. Without this, dragging
        // the inspector near the window edge can get grabbed as a window resize.
        .windowResizability(.contentMinSize)
        // Keyboard shortcuts — ⌘K palette, ⌘0–6 section nav, ⌘L drawer, ⌘R
        // refresh, ⌘⇧L theme cycle. Stock `.commands` menus; the bound model is
        // the same one ContentView renders.
        .commands {
            AppCommands(model: model)
        }

        // Native Settings scene — opened by ⌘, the app menu, or the toolbar
        // gear (SettingsLink in ContentView). ⌘, is provided by SwiftUI.
        Settings {
            SettingsView()
        }
    }
}

/// The app's keyboard-shortcut menus, ported from the Tauri global-key handler
/// (`src/routes/+page.svelte:46-128`) and the sidebar ⌘0–6 map
/// (`Sidebar.svelte:35-43`). All stock SwiftUI `Commands` — they surface in the
/// menu bar AND register the shortcuts. Async model calls are wrapped in `Task`.
struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        // A dedicated "Go" menu hosts the section-nav shortcuts (⌘0–6) so they
        // appear together with their key equivalents, like a stock View menu.
        CommandMenu("Go") {
            Button("Dashboard") { model.go(toSectionNumber: 0) }
                .keyboardShortcut("0", modifiers: .command)
            Button("Library")   { model.go(toSectionNumber: 1) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Discover")  { model.go(toSectionNumber: 2) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Trending")  { model.go(toSectionNumber: 3) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Snapshots") { model.go(toSectionNumber: 4) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Services")  { model.go(toSectionNumber: 5) }
                .keyboardShortcut("5", modifiers: .command)
            Button("Activity")  { model.go(toSectionNumber: 6) }
                .keyboardShortcut("6", modifiers: .command)

            Divider()

            // ⌘K command palette.
            Button("Command Palette…") { model.paletteOpen = true }
                .keyboardShortcut("k", modifiers: .command)
        }

        // ⌘R refresh + ⌘L drawer toggle replace the stock toolbar/sidebar
        // command group so they slot into the View menu.
        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                Task { await model.refreshCurrent() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isLoading)

            Button(model.drawerOpen ? "Hide Activity Drawer" : "Show Activity Drawer") {
                model.toggleDrawer()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Cycle Theme") { model.cycleTheme() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

/// Promotes a bare/unbundled launch (Xcode ⌘R) to a normal foreground app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Real Dock/⌘-Tab icon, loaded from BrewBrowserKit's bundle — works for
        // the bare binary (Xcode ⌘R) too, not just the build-app.sh .app.
        applyDockIcon()
    }
}
