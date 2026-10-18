import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

extension RulesCommandTests {
    @Suite(.tags(.unit))
    struct Import {
        @Test(arguments: [(["in.json"], "override"), (["in.json", "--mode", "append"], "append")])
        func modeDefaultsToOverride(arguments: [String], mode: String) throws {
            let rules = try Rules.Import.parse(arguments)
            #expect(rules.path == "in.json")
            #expect(rules.mode == mode)
        }

        @Test(arguments: [("override", WatcherSettings.ImportMode.override), ("append", .append)])
        func mergesTheFileIntoTheSettings(word: String, mode: WatcherSettings.ImportMode) throws {
            let cli = CLIHarness()
            var existing = WatcherSettings()
            existing.port = 7777
            existing.blockList = RuleSet(isEnabled: false, rules: [BlockRule(name: "mine", matching: MatchingRule())])
            try cli.environment.settings.replace(with: existing)
            let incoming = RulesCommandTests.settingsWithOneEnabledAndOneDisabledBlockRule()
            try cli.files.write(RulesCommandTests.pretty(incoming), to: "/tmp/rules.json")

            try Rules.Import.parse(["/tmp/rules.json", "--mode", word]).run(in: cli.environment)

            #expect(cli.environment.settings.value == existing.importing(incoming, mode: mode))
            #expect(cli.printed == [
                "[Import] Prepare for importing Watcher Rules. Mode = \(word), input = /tmp/rules.json", "Imported",
            ])
        }

        @Test
        func anUnknownModeIsReportedBeforeTheFileIsRead() throws {
            let cli = CLIHarness()
            let command = try Rules.Import.parse(["/tmp/missing.json", "--mode", "bogus"])
            let error = #expect(throws: ValidationError.self) { try command.run(in: cli.environment) }
            #expect(error?.message == "mode must be append or override")
            #expect(cli.printed.isEmpty)
        }

        @Test
        func anUnknownModeChangesNothing() throws {
            let cli = CLIHarness()
            try cli.files.write(RulesCommandTests.pretty(WatcherSettings()), to: "/tmp/rules.json")
            let command = try Rules.Import.parse(["/tmp/rules.json", "--mode", "bogus"])
            let error = #expect(throws: ValidationError.self) { try command.run(in: cli.environment) }
            #expect(error?.message == "mode must be append or override")
            #expect(!cli.files.paths.contains(cli.supportFile("settings.json")))
        }

        @Test
        func aFileThatIsNotWatcherJSONChangesNothing() throws {
            let cli = CLIHarness()
            cli.files.write(Data("not json".utf8), to: "/tmp/rules.json")
            let command = try Rules.Import.parse(["/tmp/rules.json"])
            #expect(throws: DecodingError.self) { try command.run(in: cli.environment) }
            #expect(!cli.files.paths.contains(cli.supportFile("settings.json")))
            #expect(cli.printed.count == 1)
        }
    }
}
