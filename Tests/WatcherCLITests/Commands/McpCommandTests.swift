import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct McpCommandTests {
    @Test(arguments: [([], nil), (["--port", "0"], 0), (["--port", "8888"], 8888)] as [([String], Int?)])
    func portDefaultsToTheStoredOne(arguments: [String], port: Int?) throws {
        #expect(try Mcp.parse(arguments).port == port)
    }

    @Test(arguments: ["65536", "-1"])
    func rejectsAPortOutsideTheRange(port: String) {
        #expect(throws: (any Error).self) { try Mcp.parse(["--port=\(port)"]) }
    }

    @Test
    func answersEachRequestLineOnStandardOutputAndStopsAtTheEndOfInput() async throws {
        let cli = CLIHarness(input: ["one", "two"])
        try await Mcp.parse(["--port", "0"]).run(in: cli.environment)
        #expect(cli.printed == ["reply to one", "reply to two"])
        #expect(cli.engine.calls == ["start 0", "stop"])
    }

    @Test
    func emptyLinesAndNotificationsGetNoReply() async throws {
        let cli = CLIHarness(input: ["", "notify", "ask", ""], engine: { settings in
            EngineFake(settings: settings, answer: { $0 == "notify" ? nil : "reply to \($0)" })
        })
        try await Mcp.parse([]).run(in: cli.environment)
        #expect(cli.printed == ["reply to ask"])
    }

    @Test
    func diagnosticsGoToStandardErrorSoStandardOutputCarriesOnlyTheProtocol() async throws {
        let cli = CLIHarness()
        try await Mcp.parse([]).run(in: cli.environment)
        cli.engine.onLog("script said hi")
        #expect(cli.printed.isEmpty)
        #expect(cli.printedToErrorOutput == [
            "[watcher] MCP server ready; proxy on 127.0.0.1:9123", "[watcher] script said hi",
        ])
    }

    @Test
    func aSystemProxyBackupLeftByACrashedRunIsRestoredAndReportedOnStandardError() async throws {
        let cli = CLIHarness.answeringNetworkSetup()
        cli.leaveSystemProxyBackup()

        try await Mcp.parse([]).run(in: cli.environment)

        #expect(cli.commands.calls.suffix(4) == CLIHarness.restoredBackupCalls)
        #expect(!cli.files.paths.contains(cli.supportFile("system-proxy-backup.json")))
        #expect(cli.printed.isEmpty)
        #expect(cli.printedToErrorOutput.contains(
            "[watcher] Put back the system proxy a previous session left pointing at Watcher"
        ))
    }

    @Test
    func failingToStartAnswersNothing() async throws {
        let cli = CLIHarness(input: ["one"], engine: { EngineFake(settings: $0, failsToStart: true) })
        let command = try Mcp.parse([])
        await #expect(throws: ExitCode.failure) { try await command.run(in: cli.environment) }
        #expect(cli.printed.isEmpty)
        #expect(cli.printedToErrorOutput == [
            "Cannot start the proxy: Failure(). Another program may be using the port; try --port.",
        ])
        #expect(cli.commands.commands.isEmpty)
    }
}
