// swift-tools-version:6.2
import PackageDescription

// brew-browser native — SwiftUI + Liquid Glass experiment (macOS 26 Tahoe).
//
// This is the spike for the native rebuild: it proves that the Liquid Glass
// chrome (NavigationSplitView sidebar, native toolbar, glass surfaces) and the
// brew subprocess layer (Process + async streaming) both work under the
// Command Line Tools toolchain on this machine, without full Xcode.
//
// Built with `swift build`; the produced executable is wrapped into a .app
// bundle by native/build-app.sh so it launches as a real, activatable Mac app.
let package = Package(
    name: "BrewBrowser",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "BrewBrowser",
            path: "Sources/BrewBrowser",
            resources: [
                // Bundled package→category map (from the Tauri app's
                // src-tauri/data/categories.json) powering the Dashboard's
                // "Top categories" donut.
                .copy("Resources/categories.json"),
                // Bundled AI enrichment (friendly names, summaries, tags,
                // use-cases, similar) for the package detail panel.
                .copy("Resources/enrichment.json")
            ]
        )
    ]
)
