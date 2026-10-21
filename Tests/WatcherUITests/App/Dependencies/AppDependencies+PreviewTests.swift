import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Previews must never reach the user's settings, defaults, login items, devices or the Mac's proxy.
@MainActor
@Suite(.tags(.unit))
struct AppDependenciesPreviewTests {
    @Test
    func previewServicesAreInertAndKeepTheirFilesInTheGivenDirectory() async throws {
        let directory = try TemporaryDirectory(prefix: "watcher-preview-test")
        let dependencies = AppDependencies.preview(in: directory.url)

        #expect(dependencies.preferences is InMemoryPreferences)
        #expect(dependencies.systemProxy is InertSystemProxy)
        #expect(!dependencies.systemProxy.hasPendingRestore)
        #expect(!dependencies.loginItem.isEnabled())
        #expect(dependencies.updater == nil)
        #expect(dependencies.devices.simulators().isEmpty)
        #expect(dependencies.devices.androidDevices().isEmpty)
        #expect(!dependencies.devices.isMacTrusted(URL(fileURLWithPath: "/ca.pem")))
        #expect(dependencies.devices.lanAddresses().isEmpty)
        #expect(await dependencies.faviconDownload(URL(fileURLWithPath: "/x")) == nil)
        #expect(dependencies.paths.directory == directory.url)
        #expect(dependencies.paths.certificateURL.path.hasPrefix(directory.url.path))
        #expect(dependencies.paths.directory != WatcherPaths.supportDirectory)
    }

    @Test
    func previewsWithoutADirectoryUseAFreshOneUnderTheTemporaryFolder() {
        let dependencies = AppDependencies.preview()
        defer { try? FileManager.default.removeItem(at: dependencies.paths.directory) }
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        #expect(dependencies.paths.directory.standardizedFileURL.path.hasPrefix(temporary))
        #expect(dependencies.paths.directory != WatcherPaths.supportDirectory)
    }
}
