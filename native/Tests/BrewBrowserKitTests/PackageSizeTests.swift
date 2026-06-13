import Testing
import Foundation
@testable import BrewBrowserKit

// Tests for the per-package size feature (#4). The pure logic — byte formatting,
// keg-path selection, and "size only when installed" — is the cross-shell parity
// core, so these cases MIRROR the Rust/Tauri tests (util/format.ts `fmtBytes`,
// the disk_usage keg-path helper) so both shells derive the SAME human string
// from the SAME bytes and resolve the SAME keg dir for a given name + kind.
//
// Parity contract:
//   Source: `du -sk` (KB*1024) on <prefix>/Cellar/<short-name> (formula, all
//   versions) or <prefix>/Caskroom/<token> (cask). Tap-qualified names use the
//   SHORT name. Non-null only when installed; nil otherwise → no Size row.
//   Formatting: B (<1 KiB) / KB 1 dec / MB 1 dec / GB 2 dec.

@Suite("Per-package size (feature #4)")
struct PackageSizeTests {

    // MARK: human byte formatter (parity with Tauri fmtBytes thresholds)

    @Test func humanBytesThresholds() {
        #expect(PackageDetailView.human(0) == "0 B")
        #expect(PackageDetailView.human(512) == "512 B")
        #expect(PackageDetailView.human(1024) == "1.0 KB")
        #expect(PackageDetailView.human(1536) == "1.5 KB")
        #expect(PackageDetailView.human(1_048_576) == "1.0 MB")
        #expect(PackageDetailView.human(5 * 1_048_576) == "5.0 MB")
        #expect(PackageDetailView.human(1_073_741_824) == "1.00 GB")
        #expect(PackageDetailView.human(Int64(2.5 * 1_073_741_824)) == "2.50 GB")
    }

    // MARK: keg-path selection (formula → Cellar, cask → Caskroom, short name)

    @Test func kegPathFormula() {
        #expect(BrewService.kegPath(prefix: "/opt/homebrew", name: "wget", kind: .formula)
            == "/opt/homebrew/Cellar/wget")
    }

    @Test func kegPathCask() {
        #expect(BrewService.kegPath(prefix: "/opt/homebrew", name: "firefox", kind: .cask)
            == "/opt/homebrew/Caskroom/firefox")
    }

    @Test func kegPathTapQualifiedUsesShortName() {
        // homebrew/core/wget must map to Cellar/wget, not the full tap path.
        #expect(BrewService.kegPath(prefix: "/opt/homebrew", name: "homebrew/core/wget", kind: .formula)
            == "/opt/homebrew/Cellar/wget")
    }

    // MARK: static parsers leave size nil (size is assigned by info(), not here)

    @Test func parseFormulaLeavesSizeNil() {
        let info = BrewService.parseFormula([
            "name": "wget",
            "full_name": "wget",
            "versions": ["stable": "1.21.4"],
            "installed": [["version": "1.21.4"]],
        ])
        #expect(info.installedSizeBytes == nil)
    }

    @Test func parseCaskLeavesSizeNil() {
        let info = BrewService.parseCask([
            "token": "firefox",
            "name": ["Firefox"],
            "version": "120.0",
            "installed": "120.0",
        ])
        #expect(info.installedSizeBytes == nil)
    }
}
