import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct WatcherPathsTests {
    private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    @Test(arguments: [[:], ["WATCHER_HOME": ""]])
    func withoutAnOverrideDataLivesInTheHomeFolder(environment: [String: String]) {
        #expect(WatcherPaths.directory(environment: environment, home: home).path == "/Users/me/.watcher")
    }

    @Test(arguments: [("/tmp/isolated", "/tmp/isolated"), ("~/elsewhere", NSHomeDirectory() + "/elsewhere")])
    func watcherHomeNamesTheFolderInstead(value: String, path: String) {
        let directory = WatcherPaths.directory(environment: ["WATCHER_HOME": value], home: home)
        #expect(directory.path == path)
    }

    @Test
    func settingsLiveInSettingsJSONInsideTheFolder() {
        let directory = URL(fileURLWithPath: "/tmp/isolated", isDirectory: true)
        #expect(WatcherPaths.settingsFile(in: directory).path == "/tmp/isolated/settings.json")
    }

    @Test
    func theSystemProxyBackupLivesInsideTheFolder() {
        let directory = URL(fileURLWithPath: "/tmp/isolated", isDirectory: true)
        #expect(WatcherPaths.systemProxyBackupFile(in: directory).path == "/tmp/isolated/system-proxy-backup.json")
    }
}
