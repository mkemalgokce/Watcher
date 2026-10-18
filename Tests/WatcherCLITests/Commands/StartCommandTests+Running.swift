import ArgumentParser
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
            await #expect(throws: ExitCode.failure) { try await command.run(in: cli.environment) }
            #expect(cli.printed.isEmpty)
            #expect(cli.commands.commands.isEmpty)
        }

        @Test
        func theEngineLogIsPrinted() async throws {
            let cli = CLIHarness()
            try await StartCommandTests.run([], in: cli) { cli.engine.onLog("busy port") }
            #expect(cli.printed.contains("[log] busy port"))
        }

        @Test(arguments: [
            (true, [LocalNetwork.Address(interface: "en0", ip: "192.168.1.20")]),
            (true, [LocalNetwork.Address(interface: "en0", ip: "10.0.0.2"), .init(interface: "en1", ip: "10.0.0.7")]),
            (true, []),
            (false, [LocalNetwork.Address(interface: "en0", ip: "192.168.1.20")]),
        ])
        func listeningOnAllInterfacesPrintsWhereDevicesReachIt(
            allInterfaces: Bool,
            addresses: [LocalNetwork.Address]
        ) async throws {
            let cli = CLIHarness(lanAddresses: addresses)
            try cli.engine.settings.update { $0.listenOnAllInterfaces = allInterfaces }
            try await StartCommandTests.run([], in: cli)
            let reachable = cli.printed.filter { $0.contains("reachable from devices") }
            let expected = addresses.map { "  reachable from devices at \($0.ip):9123  (\($0.interface))" }
            #expect(reachable == (allInterfaces ? expected : []))
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
        func aFlowThatFinishesAfterCtrlCIsNotPrinted() async throws {
            let cli = CLIHarness()
            let late = cli.engine.store.begin(.fixture(path: "/late"))

            try await StartCommandTests.run([], in: cli)
            let printedAtExit = cli.printed
            cli.engine.store.update(late.id) { $0.response = .fixture(status: 200); $0.state = .completed }

            #expect(cli.printed == printedAtExit)
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

        @Test
        func trafficThatArrivesWhileTheProxyComesUpIsContinuedAndPrinted() async throws {
            let resolution = LockedBox<BreakpointCenter.Resolution?>(nil)
            let cli = CLIHarness(engine: {
                EngineFake(settings: $0, whileStarting: { engine in
                    Task {
                        let answer = await engine.breakpoints.hold(phase: .request, request: .fixture(path: "/early"))
                        resolution.mutate { $0 = answer }
                    }
                    _ = await eventually { !engine.breakpoints.pending.isEmpty }
                    let flow = engine.store.begin(.fixture(path: "/done-early"))
                    engine.store.update(flow.id) { $0.response = .fixture(status: 200); $0.state = .completed }
                })
            })
            let url = "https://api.example.com/done-early"

            try await StartCommandTests.run([], in: cli, until: {
                resolution.value != nil && cli.printed.contains { $0.contains(url) }
            })

            #expect(resolution.value != nil)
            #expect(cli.printed.contains { $0.hasPrefix("1  200  GET  \(url)") })
        }

        @Test
        func aHeldResponseProceedsWithTheSameRequestAndResponse() async throws {
            let cli = CLIHarness()
            let resolution = LockedBox<BreakpointCenter.Resolution?>(nil)
            try await StartCommandTests.run([], in: cli, until: { resolution.value != nil }) {
                Task {
                    let answer = await cli.engine.breakpoints.hold(
                        phase: .response, request: .fixture(path: "/held"), response: .fixture(status: 418)
                    )
                    resolution.mutate { $0 = answer }
                }
            }
            guard case let .proceed(request, response) = try #require(resolution.value) else {
                Issue.record("the held response was aborted"); return
            }
            #expect(request == .fixture(path: "/held"))
            #expect(response == .fixture(status: 418))
            #expect(cli.printed.contains {
                $0 == "[breakpoint] response GET https://api.example.com/held (continued; use the app to edit)"
            })
        }

        @Test
        func twoMessagesHeldAtOnceAreBothContinuedAndPrinted() async throws {
            let cli = CLIHarness()
            let resolved = LockedBox(0)
            try await StartCommandTests.run([], in: cli, until: { resolved.value == 2 }) {
                for path in ["/one", "/two"] {
                    Task {
                        _ = await cli.engine.breakpoints.hold(phase: .request, request: .fixture(path: path))
                        resolved.mutate { $0 += 1 }
                    }
                }
            }
            #expect(cli.printed.filter { $0.hasPrefix("[breakpoint]") }.count == 2)
        }

        @Test
        func anEngineThatFailsToStopStillSavesTheSessionAndEndsNormally() async throws {
            let cli = CLIHarness(engine: { EngineFake(settings: $0, failsToStop: true) })
            try await StartCommandTests.run(["--csv", "/tmp/s.csv"], in: cli)
            #expect(cli.files.contents(of: "/tmp/s.csv") != nil)
            #expect(cli.engine.calls == ["start any", "stop"])
        }

        @Test
        func theSystemProxyIsPutBackBeforeTheSessionIsSavedAndTheEngineStopped() async throws {
            let files = FileAccessFake()
            let log = LockedBox<[String]>([])
            let commands = CommandRunnerSpy.networkSetup(onRun: { command in
                guard command.arguments.first == "-setwebproxystate", command.arguments.contains("off") else { return }
                log.mutate { $0.append(files.paths.contains("/tmp/s.har") ? "disable after save" : "disable") }
            })
            let cli = CLIHarness(files: files, commands: commands, engine: { EngineFake(settings: $0, log: log) })

            try await StartCommandTests.run(["--system-proxy", "--har", "/tmp/s.har"], in: cli)

            #expect(log.value.filter { $0.hasPrefix("disable") || $0 == "stop" } == ["disable", "stop"])
            #expect(files.paths.contains("/tmp/s.har"))
        }
    }
}
