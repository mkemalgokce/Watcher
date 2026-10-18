import Foundation
import Testing
@testable import WatcherUI

@Suite(.tags(.unit))
struct AppInfoTests {
    private func info(
        identifier: String? = "dev.watcher.app", version: String? = "1.2", build: String? = "34"
    ) -> AppInfo {
        AppInfo(
            bundleIdentifier: identifier, shortVersion: version, buildNumber: build,
            operatingSystem: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 2),
            architecture: "arm64", homeDirectory: "/Users/ada"
        )
    }

    private static let versionCases: [(String?, String?, String?, String)] = [
        ("dev.watcher.app", "1.2", "34", "Version 1.2 (34)"), ("dev.watcher.app", "1.2", nil, "Version 1.2 (?)"),
        ("dev.watcher.app", nil, "34", "Development build"), ("com.apple.dt.xctest", "16.0", "1", "Development build"),
        (nil, "1.2", "34", "Development build"),
    ]

    @Test(arguments: versionCases)
    func onlyAPackagedWatcherReportsItsVersion(
        identifier: String?, version: String?, build: String?, text: String
    ) {
        #expect(info(identifier: identifier, version: version, build: build).versionText == text)
    }

    @Test
    func theDiagnosticsNameTheBuildTheSystemAndTheChip() {
        #expect(info().diagnostics == "Watcher Version 1.2 (34) · macOS 26.1.2 · arm64")
        #expect(info(identifier: nil).diagnostics == "Watcher Development build · macOS 26.1.2 · arm64")
    }

    @Test(arguments: [
        ("/Users/ada/.watcher", "~/.watcher"), ("/Users/ada", "~"), ("/Users/adam/x", "/Users/adam/x"),
        ("/opt/Users/ada/x", "/opt/Users/ada/x"), ("/tmp", "/tmp"),
    ])
    func thePathShowsTheHomeFolderAsATilde(path: String, shown: String) {
        #expect(info().abbreviatingHome(path) == shown)
    }
}
