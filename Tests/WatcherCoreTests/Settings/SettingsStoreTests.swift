import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SettingsStoreTests {
    private let temporary: TemporaryDirectory
    private var directory: URL {
        temporary.url
    }

    private var url: URL {
        directory.appendingPathComponent("settings.json")
    }

    init() throws {
        temporary = try TemporaryDirectory(prefix: "watcher-settings")
    }

    @Test
    func missingOrValidFileHasNoLoadIssue() throws {
        let fresh = SettingsStore(url: url)
        #expect(fresh.loadIssue == nil)
        try fresh.update { $0.port = 7777 }
        #expect(SettingsStore(url: url).loadIssue == nil)
        #expect(SettingsStore(url: url).value.port == 7777)
    }

    @Test
    func wrongTypedFileIsMovedAsideInsteadOfOverwritten() throws {
        let original = Data(#"{"port":"9090"}"#.utf8)
        try original.write(to: url)

        let store = SettingsStore(url: url)
        try store.update { $0.maxFlows = 5 }

        let backup = try #require(backups().first, "the unreadable file must be kept")
        #expect(try Data(contentsOf: backup) == original)
        #expect(store.loadIssue?.movedTo?.lastPathComponent == backup.lastPathComponent)
        let pattern = #"^settings\.json\.unreadable-\d{8}-\d{6}$"#
        #expect(backup.lastPathComponent.range(of: pattern, options: .regularExpression) != nil)
        #expect(SettingsStore(url: url).value.maxFlows == 5)
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
        try Data(broken.utf8).write(to: url)

        let store = SettingsStore(url: url)
        try store.replace(with: WatcherSettings())

        let backup = try #require(backups().first)
        #expect(try String(contentsOf: backup, encoding: .utf8).contains("keep me"))
        #expect(store.loadIssue?.reason != nil)
    }

    @Test
    func secondUnreadableFileDoesNotReplaceTheFirstBackup() throws {
        try Data("first".utf8).write(to: url)
        let store = SettingsStore(url: url)
        try Data("second".utf8).write(to: url)
        store.reloadIfChanged()

        let contents = try Set(backups().map { try String(contentsOf: $0, encoding: .utf8) })
        #expect(contents == ["first", "second"])
    }

    @Test
    func writesAreRefusedWhileAnUnreadableFileCannotBeMovedAside() throws {
        let original = Data("not json".utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let store = SettingsStore(url: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        #expect(store.loadIssue != nil)
        #expect(store.loadIssue?.movedTo == nil)
        #expect(throws: (any Error).self) { try store.update { $0.port = 1 } }
        #expect(throws: (any Error).self) { try store.replace(with: WatcherSettings()) }
        #expect(try Data(contentsOf: url) == original)

        try FileManager.default.removeItem(at: url)
        #expect(throws: Never.self, "once the file is gone nothing can be lost") { try store.update { $0.port = 1 } }
    }

    @Test
    func concurrentUpdatesAreNotLost() throws {
        let store = SettingsStore(url: url)
        try store.update { $0.maxFlows = 0 }
        let failures = LockedBox<[any Error]>([])
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            do { try store.update { $0.maxFlows += 1 } } catch { failures.mutate { $0.append(error) } }
        }
        #expect(failures.value.isEmpty)
        #expect(store.value.maxFlows == 100)
        #expect(SettingsStore(url: url).value.maxFlows == 100)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test
    func settingsPersistAndReload() throws {
        let first = SettingsStore(url: url)
        try first.update {
            $0.port = 7777
            $0.blockList = RuleSet(isEnabled: true, rules: [BlockRule(matching: MatchingRule(pattern: "x"))])
        }
        let second = SettingsStore(url: url)
        #expect(second.value.port == 7777)
        #expect(second.value.blockList.rules.count == 1)
    }

    @Test
    func settingsFromAnOlderVersionStillLoadWithDefaults() throws {
        let old = #"{"port": 1234, "noCaching": true, "externalProxy": {"isEnabled": true, "host": "h", "port": 1}}"#
        try Data(old.utf8).write(to: url)
        let settings = SettingsStore(url: url).value
        #expect(settings.port == 1234)
        #expect(settings.noCaching)
        #expect(settings.externalProxy.host == "h")
        #expect(settings.socks == SocksSettings())
        #expect(!settings.listenOnAllInterfaces)
    }

    private func backups() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.json.unreadable-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
