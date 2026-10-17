import Foundation
@testable import WatcherCore
import XCTest

final class SettingsStoreTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("watcher-settings-\(UUID().uuidString)")
    private var url: URL {
        directory.appendingPathComponent("settings.json")
    }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingOrValidFileHasNoLoadIssue() throws {
        let fresh = SettingsStore(url: url)
        XCTAssertNil(fresh.loadIssue)
        try fresh.update { $0.port = 7777 }
        XCTAssertNil(SettingsStore(url: url).loadIssue)
        XCTAssertEqual(SettingsStore(url: url).value.port, 7777)
    }

    func testWrongTypedFileIsMovedAsideInsteadOfOverwritten() throws {
        let original = Data(#"{"port":"9090"}"#.utf8)
        try original.write(to: url)

        let store = SettingsStore(url: url)
        try store.update { $0.maxFlows = 5 }

        let backup = try XCTUnwrap(backups().first, "the unreadable file must be kept")
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(store.loadIssue?.movedTo?.lastPathComponent, backup.lastPathComponent)
        let pattern = #"^settings\.json\.unreadable-\d{8}-\d{6}$"#
        XCTAssertNotNil(backup.lastPathComponent.range(of: pattern, options: .regularExpression))
        XCTAssertEqual(SettingsStore(url: url).value.maxFlows, 5)
    }

    func testRuleMissingAFieldKeepsEveryRuleInTheBackup() throws {
        var settings = WatcherSettings()
        let rule = BlockRule(name: "keep me", matching: MatchingRule(pattern: "a"))
        settings.blockList = RuleSet(isEnabled: true, rules: [rule])
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(settings), encoding: .utf8))
        let broken = encoded.replacingOccurrences(of: #","hidesRequest":false"#, with: "")
            .replacingOccurrences(of: #""hidesRequest":false,"#, with: "")
        XCTAssertFalse(broken.contains("hidesRequest"))
        try Data(broken.utf8).write(to: url)

        let store = SettingsStore(url: url)
        try store.replace(with: WatcherSettings())

        let backup = try XCTUnwrap(backups().first)
        XCTAssertTrue(try String(contentsOf: backup, encoding: .utf8).contains("keep me"))
        XCTAssertNotNil(store.loadIssue?.reason)
    }

    func testSecondUnreadableFileDoesNotReplaceTheFirstBackup() throws {
        try Data("first".utf8).write(to: url)
        let store = SettingsStore(url: url)
        try Data("second".utf8).write(to: url)
        store.reloadIfChanged()

        let contents = try Set(backups().map { try String(contentsOf: $0, encoding: .utf8) })
        XCTAssertEqual(contents, ["first", "second"])
    }

    func testWritesAreRefusedWhileAnUnreadableFileCannotBeMovedAside() throws {
        let original = Data("not json".utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let store = SettingsStore(url: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        XCTAssertNotNil(store.loadIssue)
        XCTAssertNil(store.loadIssue?.movedTo)
        XCTAssertThrowsError(try store.update { $0.port = 1 })
        XCTAssertThrowsError(try store.replace(with: WatcherSettings()))
        XCTAssertEqual(try Data(contentsOf: url), original)

        try FileManager.default.removeItem(at: url)
        XCTAssertNoThrow(try store.update { $0.port = 1 }, "once the file is gone nothing can be lost")
    }

    func testConcurrentUpdatesAreNotLost() throws {
        let store = SettingsStore(url: url)
        try store.update { $0.maxFlows = 0 }
        let failures = Failures()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            do { try store.update { $0.maxFlows += 1 } } catch { failures.add(error) }
        }
        XCTAssertEqual(failures.count, 0)
        XCTAssertEqual(store.value.maxFlows, 100)
        XCTAssertEqual(SettingsStore(url: url).value.maxFlows, 100)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    private func backups() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.json.unreadable-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

private final class Failures: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []
    var count: Int {
        lock.withLock { errors.count }
    }

    func add(_ error: Error) {
        lock.withLock { errors.append(error) }
    }
}
