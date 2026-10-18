import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct ToolCommandTests {
    @Test(arguments: [("on", Tool.State.on), ("off", Tool.State.off)])
    func readsTheToolAndItsState(word: String, state: Tool.State) throws {
        let tool = try Tool.parse(["map-local", word])
        #expect(tool.tool == .mapLocal)
        #expect(tool.state == state)
    }

    @Test(arguments: [[], ["map-local"], ["map-local", "maybe"], ["teleport", "on"]])
    func rejectsAMissingOrUnknownValue(arguments: [String]) {
        #expect(throws: (any Error).self) { try Tool.parse(arguments) }
    }

    @Test
    func helpNamesEveryTool() {
        let help = Tool.helpMessage()
        for name in ToolName.allCases.map(\.rawValue) {
            #expect(help.contains(name), "\(name) missing from: \(help)")
        }
    }

    @Test
    func switchingOnSavesItInTheSettingsARunningProxyReads() throws {
        let cli = CLIHarness()
        try Tool.parse(["map-local", "on"]).run(in: cli.environment)
        #expect(cli.environment.settings.value.mapLocal.isEnabled)
        #expect(cli.printed == ["map-local: on"])
    }

    @Test
    func switchingOffKeepsTheOtherSettings() throws {
        let cli = CLIHarness()
        try cli.environment.settings.update { $0.port = 7777; $0.noCaching = true; $0.mapLocal.isEnabled = true }
        try Tool.parse(["map-local", "off"]).run(in: cli.environment)
        let settings = cli.environment.settings.value
        #expect(!settings.mapLocal.isEnabled)
        #expect(settings.port == 7777)
        #expect(settings.noCaching)
        #expect(cli.printed == ["map-local: off"])
    }

    @Test
    func printsNothingWhenTheSettingsCannotBeSaved() throws {
        let cli = CLIHarness()
        cli.files.fail(.writePrivately)
        let command = try Tool.parse(["no-caching", "on"])
        #expect(throws: FileAccessFake.Failure(operation: .writePrivately)) { try command.run(in: cli.environment) }
        #expect(cli.printed.isEmpty)
    }
}
