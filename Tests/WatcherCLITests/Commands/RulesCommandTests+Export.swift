import ArgumentParser
import Foundation
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
            #expect(export.mode == mode)
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
        func anUnknownModeFailsBeforeWritingAnything(mode: String) throws {
            let cli = CLIHarness()
            let command = try Rules.Export.parse(["/tmp/rules.json", "--mode", mode])
            let error = #expect(throws: ValidationError.self) { try command.run(in: cli.environment) }
            #expect(error?.message == "mode must be all or enabledRules")
            #expect(cli.files.contents(of: "/tmp/rules.json") == nil)
            #expect(cli.printed.isEmpty)
        }

        @Test
        func aFailedWriteIsReported() throws {
            let cli = CLIHarness()
            cli.files.fail(.writeAtomically)
            let command = try Rules.Export.parse(["/tmp/rules.json"])
            #expect(throws: FileAccessFake.Failure(operation: .writeAtomically)) {
                try command.run(in: cli.environment)
            }
        }
    }
}
