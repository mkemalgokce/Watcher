import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// The store on a real disk: what the in-memory fake cannot show.
@Suite(.timeLimit(.minutes(1)), .tags(.integration))
struct SettingsStoreTests {
    private let temporary: TemporaryDirectory

    init() throws {
        temporary = try TemporaryDirectory(prefix: "watcher-settings")
    }

    @Test
    func settingsAreSavedOwnerOnlyAndReadBackByAnotherStore() throws {
        let url = temporary.url.appendingPathComponent("nested/settings.json")
        try SettingsStore(url: url).update { $0.port = 7777 }

        #expect(SettingsStore(url: url).value.port == 7777)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test
    func anUnreadableFileIsMovedAsideOnDisk() throws {
        let url = temporary.url.appendingPathComponent("settings.json")
        try Data("not json".utf8).write(to: url)
        let store = SettingsStore(url: url)
        let backup = try #require(store.loadIssue?.movedTo)
        #expect(try Data(contentsOf: backup) == Data("not json".utf8))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
