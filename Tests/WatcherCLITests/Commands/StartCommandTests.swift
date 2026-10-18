import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct StartCommandTests {
    @Test
    func defaultsUseTheStoredPortAndChangeNothingElse() throws {
        let start = try Start.parse([])
        #expect(start.port == nil)
        #expect(!start.noDecrypt)
        #expect(start.har == nil)
        #expect(start.csv == nil)
        #expect(!start.systemProxy)
    }

    @Test
    func readsEveryOption() throws {
        let arguments = ["--port", "0", "--no-decrypt", "--har", "~/x.har", "--csv", "y.csv", "--system-proxy"]
        let start = try Start.parse(arguments)
        #expect(start.port == 0)
        #expect(start.noDecrypt)
        #expect(start.har == "~/x.har")
        #expect(start.csv == "y.csv")
        #expect(start.systemProxy)
    }

    @Test(arguments: [["--port"], ["--port", "eighty"], ["--har"]])
    func rejectsAMissingOrMalformedValue(arguments: [String]) {
        #expect(throws: (any Error).self) { try Start.parse(arguments) }
    }

    @Test(arguments: ["0", "1", "65535"])
    func acceptsAnyPortASocketCanUseAndZeroForAnyFreeOne(port: String) throws {
        #expect(try Start.parse(["--port", port]).port == Int(port))
    }

    @Test(arguments: ["65536", "70000", "-1"])
    func rejectsAPortOutsideTheRange(port: String) {
        #expect(throws: (any Error).self) { try Start.parse(["--port=\(port)"]) }
    }

    /// Runs `start` until it waits for Ctrl-C, then runs `whileRunning`, waits for `until`, and presses Ctrl-C.
    static func run(
        _ arguments: [String],
        in cli: CLIHarness,
        until done: @escaping () -> Bool = { true },
        whileRunning: () -> Void = {}
    ) async throws {
        let command = try Start.parse(arguments)
        let environment = cli.environment
        let running = Task { try await command.run(in: environment) }
        let waiting = await eventually(timeout: 30) { cli.shutdown.isAwaited }
        whileRunning()
        let finished = await eventually(timeout: 30, done)
        cli.shutdown.fire()
        try await running.value
        #expect(waiting, "start never waited for Ctrl-C")
        #expect(finished, "start never got there: \(cli.printed)")
    }
}
