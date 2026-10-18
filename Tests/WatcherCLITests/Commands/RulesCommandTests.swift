import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RulesCommandTests {
    @Test
    func subcommandsAreExportImportAndImportCharles() throws {
        #expect(try Rules.parseAsRoot(["export", "a.json"]) is Rules.Export)
        #expect(try Rules.parseAsRoot(["import", "a.json"]) is Rules.Import)
        #expect(try Rules.parseAsRoot(["import-charles", "a.xml"]) is ImportCharles)
    }

    @Test(arguments: [["export"], ["import"], ["import-charles"]])
    func everySubcommandNeedsAPath(arguments: [String]) {
        #expect(throws: (any Error).self) { try Rules.parseAsRoot(arguments) }
    }

    static func settingsWithOneEnabledAndOneDisabledBlockRule() -> WatcherSettings {
        var settings = WatcherSettings()
        let match = MatchingRule(pattern: "*.example.com")
        settings.blockList = RuleSet(isEnabled: true, rules: [
            BlockRule(name: "on", matching: match), BlockRule(name: "off", isEnabled: false, matching: match),
        ])
        return settings
    }

    static func pretty(_ settings: WatcherSettings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }
}
