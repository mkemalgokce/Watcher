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
            #expect(rules.mode.rawValue == mode)
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

        @Test(arguments: ["bogus", "", "Append"])
        func anUnknownModeIsRejectedWhenParsing(mode: String) {
            #expect {
                try Rules.Import.parse(["/tmp/rules.json", "--mode", mode])
            } throws: {
                Rules.Import.message(for: $0).contains("--mode")
            }
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

        @Test
        func aSettingsFileThatCannotBeWrittenPrintsNoImportedLine() throws {
            let cli = CLIHarness()
            try cli.files.write(RulesCommandTests.pretty(WatcherSettings()), to: "/tmp/rules.json")
            cli.files.fail(.writePrivately)
            let command = try Rules.Import.parse(["/tmp/rules.json"])
            #expect(throws: FileAccessFake.Failure(operation: .writePrivately)) { try command.run(in: cli.environment) }
            #expect(!cli.printed.contains("Imported"))
        }
    }
}
