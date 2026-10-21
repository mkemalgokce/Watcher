import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SettingsStoreTests {
    private let path = "/home/.watcher/settings.json"
    private let files = FileAccessFake()
    /// 2001-01-01 00:00:10 UTC.
    private let now = Date(timeIntervalSinceReferenceDate: 10)

    private var url: URL {
        URL(fileURLWithPath: path)
    }

    private func store() -> SettingsStore {
        SettingsStore(url: url, files: files.access, now: { [now] in now })
    }

    private var backups: [String] {
        files.paths.filter { $0.hasPrefix(path + ".unreadable-") }.sorted()
    }

    @Test
    func missingOrValidFileHasNoLoadIssue() throws {
        let fresh = store()
        #expect(fresh.loadIssue == nil)
        try fresh.update { $0.port = 7777 }
        #expect(store().loadIssue == nil)
        #expect(store().value.port == 7777)
    }

    @Test
    func writesAreReadableOnlyByTheOwnerFromTheStartAndCreateTheFolder() throws {
        let store = store()
        try store.replace(with: WatcherSettings())
        try store.update { $0.port = 7777 }
        #expect(files.permissionHistory(of: path) == [0o600, 0o600], "the file may hold proxy credentials")
        #expect(files.folders == ["/home/.watcher"])
    }

    @Test
    func wrongTypedFileIsMovedAsideInsteadOfOverwritten() throws {
        let original = Data(#"{"port":"9090"}"#.utf8)
        files.write(original, to: path)

        let store = store()
        try store.update { $0.maxFlows = 5 }

        #expect(backups == [path + ".unreadable-20010101-000010"])
        #expect(files.contents(of: backups[0]) == original)
        #expect(store.loadIssue?.movedTo?.path == backups.first)
        #expect(self.store().value.maxFlows == 5)
    }

    @Test
    func ruleMissingAFieldKeepsEveryRuleInTheBackup() throws {
        var settings = WatcherSettings()
        let rule = BlockRule(name: "keep me", matching: MatchingRule(pattern: "a"))
        settings.blockList = RuleSet(isEnabled: true, rules: [rule])
        let encoded = try #require(String(data: JSONEncoder().encode(settings), encoding: .utf8))
        let broken = encoded.replacingOccurrences(of: #","hidesRequest":false"#, with: "")
            .replacingOccurrences(of: #""hidesRequest":false,"#, with: "")
        #expect(!broken.contains("hidesRequest"))
        files.write(Data(broken.utf8), to: path)

        let store = store()
        try store.replace(with: WatcherSettings())

        let backup = try #require(backups.first.flatMap(files.contents))
        #expect(String(bytes: backup, encoding: .utf8)?.contains("keep me") == true)
        #expect(store.loadIssue?.reason != nil)
    }

    @Test
    func laterUnreadableFilesGetNumberedBackupNames() {
        files.write(Data("first".utf8), to: path)
        let store = store()
        files.write(Data("second".utf8), to: path)
        store.reloadIfChanged()
        files.write(Data("third".utf8), to: path)
        store.reloadIfChanged()

        let stamp = path + ".unreadable-20010101-000010"
        #expect(backups == [stamp, stamp + "-2", stamp + "-3"])
        #expect(backups.compactMap(files.contents) == ["first", "second", "third"].map { Data($0.utf8) })
    }

    @Test
    func writesAreRefusedWhileAnUnreadableFileCannotBeMovedAside() throws {
        let original = Data("not json".utf8)
        files.write(original, to: path)
        files.fail(.move)
        let store = store()

        #expect(store.loadIssue != nil)
        #expect(store.loadIssue?.movedTo == nil)
        #expect(throws: SettingsStoreError.unreadableFileInPlace(url)) { try store.update { $0.port = 1 } }
        #expect(throws: SettingsStoreError.unreadableFileInPlace(url)) { try store.replace(with: WatcherSettings()) }
        #expect(files.contents(of: path) == original)

        files.remove(path)
        #expect(throws: Never.self, "once the file is gone nothing can be lost") { try store.update { $0.port = 1 } }
    }

    @Test
    func aFailedWriteThrowsAndKeepsTheOldValue() throws {
        let store = store()
        try store.update { $0.port = 1 }
        files.fail(.writePrivately)
        #expect(throws: FileAccessFake.Failure(operation: .writePrivately)) { try store.update { $0.port = 2 } }
        #expect(store.value.port == 1)
    }

    @Test
    func reloadReportsWhetherAnotherProcessChangedTheFile() throws {
        let store = store()
        try store.update { $0.port = 1 }
        #expect(!store.reloadIfChanged(), "its own write is not a change")

        var edited = WatcherSettings()
        edited.port = 2
        try files.write(JSONEncoder().encode(edited), to: path)
        #expect(store.reloadIfChanged())
        #expect(store.value.port == 2)
        #expect(!store.reloadIfChanged())
    }

    @Test
    func aCleanLoadClearsAnEarlierIssue() throws {
        files.write(Data("broken".utf8), to: path)
        let store = store()
        #expect(store.loadIssue != nil)
        try files.write(JSONEncoder().encode(WatcherSettings()), to: path)
        #expect(store.reloadIfChanged())
        #expect(store.loadIssue == nil)
    }

    @Test
    func anUnreadableFileIsNotAChange() {
        files.write(Data("{}".utf8), to: path)
        files.fail(.read)
        let store = store()
        #expect(!store.reloadIfChanged())
        #expect(store.loadIssue == nil)
    }

    @Test
    func concurrentUpdatesAreNotLost() throws {
        let store = store()
        try store.update { $0.maxFlows = 0 }
        let failures = LockedBox<[any Error]>([])
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            do { try store.update { $0.maxFlows += 1 } } catch { failures.mutate { $0.append(error) } }
        }
        #expect(failures.value.isEmpty)
        #expect(store.value.maxFlows == 100)
        #expect(self.store().value.maxFlows == 100)
    }

    @Test
    func settingsFromAnOlderVersionStillLoadWithDefaults() {
        let old = #"{"port": 1234, "noCaching": true, "externalProxy": {"isEnabled": true, "host": "h", "port": 1}}"#
        files.write(Data(old.utf8), to: path)
        let settings = store().value
        #expect(settings.port == 1234)
        #expect(settings.noCaching)
        #expect(settings.externalProxy.host == "h")
        #expect(settings.socks == SocksSettings())
        #expect(!settings.listenOnAllInterfaces)
    }
}

struct SessionRetentionDefaultTests {
    @Test func aFreshSettingsFileKeepsABoundedSession() {
        #expect(WatcherSettings().maxFlows == WatcherSettings.defaultMaxFlows)
        #expect(WatcherSettings.defaultMaxFlows > 0)
    }
}
