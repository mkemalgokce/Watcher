import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

extension RulesCommandTests {
    @Suite(.tags(.unit))
    struct Export {
        @Test(arguments: [(["out.json"], "all"), (["out.json", "--mode", "enabledRules"], "enabledRules")])
        func modeDefaultsToAll(arguments: [String], mode: String) throws {
            let export = try Rules.Export.parse(arguments)
            #expect(export.path == "out.json")
            #expect(export.mode.rawValue == mode)
        }

        @Test(arguments: [("all", WatcherSettings.ExportMode.all), ("enabledRules", .enabledRules)])
        func writesTheRulesAsSortedPrettyJSON(word: String, mode: WatcherSettings.ExportMode) throws {
            let cli = CLIHarness()
            let settings = RulesCommandTests.settingsWithOneEnabledAndOneDisabledBlockRule()
            try cli.environment.settings.replace(with: settings)

            try Rules.Export.parse(["/tmp/rules.json", "--mode", word]).run(in: cli.environment)

            let expected = try RulesCommandTests.pretty(settings.exported(mode))
            #expect(cli.files.contents(of: "/tmp/rules.json") == expected)
            #expect(cli.printed == [
                "[Export] Prepare for exporting Watcher Rules. Mode = \(word), output = /tmp/rules.json",
            ])
        }

        @Test
        func aTildeDestinationIsInTheHomeFolder() throws {
            let cli = CLIHarness()
            try Rules.Export.parse(["~/rules.json"]).run(in: cli.environment)
            #expect(cli.files.paths.contains("/Users/me/rules.json"))
        }

        @Test(arguments: ["bogus", "", "ALL"])
        func anUnknownModeIsRejectedWhenParsing(mode: String) {
            #expect {
                try Rules.Export.parse(["/tmp/rules.json", "--mode", mode])
            } throws: {
                Rules.Export.message(for: $0).contains("--mode")
            }
        }

        @Test
        func aFailedWriteIsReported() throws {
            let cli = CLIHarness()
            cli.files.fail(.writeAtomically)
            let command = try Rules.Export.parse(["/tmp/rules.json"])
            #expect(throws: FileAccessFake.Failure(operation: .writeAtomically)) {
                try command.run(in: cli.environment)
            }
            #expect(cli.printed == [
                "[Export] Prepare for exporting Watcher Rules. Mode = all, output = /tmp/rules.json",
            ])
        }

        @Test
        func exportingPrintsOnlyWhereItPreparesToWrite() throws {
            let cli = CLIHarness()
            try Rules.Export.parse(["/tmp/rules.json"]).run(in: cli.environment)
            #expect(cli.printed.count == 1)
        }
    }
}
