import Foundation
import Testing
@testable import watcher_cli
@testable import WatcherCore
import WatcherTestSupport

extension StartCommandTests {
    @Suite(.tags(.unit), .timeLimit(.minutes(1)))
    struct Running {
        @Test(arguments: [([], "start any"), (["--port", "0"], "start 0"), (["--port", "8888"], "start 8888")])
        func startsTheProxyAndStopsItOnCtrlC(arguments: [String], start: String) async throws {
            let cli = CLIHarness()
            try await StartCommandTests.run(arguments, in: cli)
            #expect(cli.engine.calls == [start, "stop"])
            #expect(cli.printed.first == "Watcher listening on 127.0.0.1:9123")
        }

        @Test
        func failingToStartStopsBeforePrintingOrTouchingTheSystemProxy() async throws {
            let cli = CLIHarness(engine: { EngineFake(settings: $0, failsToStart: true) })
            let command = try Start.parse(["--system-proxy"])
            await #expect(throws: EngineFake.Failure()) { try await command.run(in: cli.environment) }
            #expect(cli.printed.isEmpty)
            #expect(cli.commands.commands.isEmpty)
        }

        @Test
        func theEngineLogIsPrinted() async throws {
            let cli = CLIHarness()
            try await StartCommandTests.run([], in: cli) { cli.engine.onLog("busy port") }
            #expect(cli.printed.contains("[log] busy port"))
        }

        @Test(arguments: [true, false])
        func listeningOnAllInterfacesPrintsWhereDevicesReachIt(allInterfaces: Bool) async throws {
            let addresses = [LocalNetwork.Address(interface: "en0", ip: "192.168.1.20")]
            let cli = CLIHarness(lanAddresses: addresses)
            try cli.engine.settings.update { $0.listenOnAllInterfaces = allInterfaces }
            try await StartCommandTests.run([], in: cli)
            let reachable = cli.printed.filter { $0.contains("reachable from devices") }
            #expect(reachable == (allInterfaces ? ["  reachable from devices at 192.168.1.20:9123  (en0)"] : []))
        }

        @Test(arguments: [(["--no-decrypt"], false), ([], true)])
        func noDecryptTunnelsHTTPSFromTheStartWithoutChangingTheSettings(
            arguments: [String],
            decrypts: Bool
        ) async throws {
            let cli = CLIHarness()
            try cli.engine.settings.update { $0.sslProxying.include = ["*"] }
            try await StartCommandTests.run(arguments, in: cli)
            #expect(cli.engine.decryptedHTTPSAtStart == decrypts)
            #expect(cli.engine.settings.value.sslProxying.include == ["*"])
        }

        @Test
        func finishedFlowsArePrintedOnce() async throws {
            let cli = CLIHarness()
            let url = "https://api.example.com/e2e"
            try await StartCommandTests.run([], in: cli, until: { cli.printed.contains { $0.contains(url) } }) {
                let flow = cli.engine.store.begin(.fixture(path: "/e2e"))
                for _ in 0 ..< 3 {
                    cli.engine.store.update(flow.id) { $0.response = .fixture(status: 201); $0.state = .completed }
                }
            }
            #expect(cli.printed.filter { $0.contains(url) } == ["1  201  GET  \(url)  0ms"])
        }

        @Test
        func heldMessagesContinueUnchangedAndArePrinted() async throws {
            let cli = CLIHarness()
            let resolution = LockedBox<BreakpointCenter.Resolution?>(nil)
            try await StartCommandTests.run([], in: cli, until: { resolution.value != nil }) {
                Task {
                    let answer = await cli.engine.breakpoints.hold(phase: .request, request: .fixture(path: "/held"))
                    resolution.mutate { $0 = answer }
                }
            }
            guard case let .proceed(request, response) = try #require(resolution.value) else {
                Issue.record("the held request was aborted"); return
            }
            #expect(request == .fixture(path: "/held"))
            #expect(response == nil)
            #expect(cli.printed.contains(
                "[breakpoint] request GET https://api.example.com/held (continued; use the app to edit)"
            ))
        }
    }
}
