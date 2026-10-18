import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
@testable import WatcherCore
import WatcherTestSupport

extension StartCommandTests {
    @Suite(.tags(.unit), .timeLimit(.minutes(1)))
    struct ShuttingDown {
        @Test
        func theSystemProxyPointsAtTheBoundPortUntilTheProxyStops() async throws {
            let log = LockedBox<[String]>([])
            let networkSetup = NetworkSetupSpy()
            let commands = CommandRunnerSpy(respond: { command in
                log.mutate { $0.append(command.arguments[0]) }
                return CommandResult(status: 0, output: Data(networkSetup.run(command.arguments).utf8))
            })
            let cli = CLIHarness(commands: commands, engine: { EngineFake(settings: $0, log: log) })

            try await StartCommandTests.run(["--system-proxy"], in: cli)

            #expect(cli.commands.calls.contains("networksetup -setwebproxy Wi-Fi 127.0.0.1 9123"))
            let order = log.value.filter { ["start any", "-setwebproxy", "-setwebproxystate", "stop"].contains($0) }
            #expect(order == ["start any", "-setwebproxy", "-setwebproxystate", "stop"])
            #expect(!cli.files.paths.contains(cli.supportFile("system-proxy-backup.json")))
        }

        /// A crashed run leaves its backup behind; the next `--system-proxy` session must restore the user's proxy from
        /// it, not the one that crashed run pointed at Watcher.
        @Test
        func aBackupLeftByACrashedRunIsWhatTheSessionRestores() async throws {
            let cli = CLIHarness.answeringNetworkSetup()
            cli.leaveSystemProxyBackup()

            try await StartCommandTests.run(["--system-proxy"], in: cli)

            #expect(!cli.commands.calls.contains { $0.contains("-getwebproxy") })
            #expect(cli.commands.calls.suffix(4) == CLIHarness.restoredBackupCalls)
            #expect(!cli.files.paths.contains(cli.supportFile("system-proxy-backup.json")))
        }

        @Test
        func withoutTheFlagABackupLeftByACrashedRunIsRestoredAtTheStart() async throws {
            let cli = CLIHarness.answeringNetworkSetup()
            cli.leaveSystemProxyBackup()

            try await StartCommandTests.run([], in: cli)

            #expect(cli.commands.calls.suffix(4) == CLIHarness.restoredBackupCalls)
            #expect(!cli.files.paths.contains(cli.supportFile("system-proxy-backup.json")))
            #expect(cli.printed.contains("Put back the system proxy a previous session left pointing at Watcher"))
        }

        @Test
        func aLeftoverSystemProxyThatCannotBePutBackIsNotReportedAsRestored() async throws {
            let failing = CommandRunnerSpy(result: CommandResult(status: 14, output: Data("not allowed".utf8)))
            let cli = CLIHarness(commands: failing)
            cli.leaveSystemProxyBackup()

            try await StartCommandTests.run([], in: cli)

            #expect(!cli.printed.contains { $0.hasPrefix("Put back") })
            #expect(cli.engine.calls == ["start any", "stop"])
        }

        @Test
        func aStopRequestedWhileTheSystemProxyIsBeingSetStillPutsItBack() async throws {
            let shutdown = ShutdownTrigger()
            let networkSetup = NetworkSetupSpy()
            let commands = CommandRunnerSpy(respond: { command in
                if command.arguments[0] == "-setwebproxy" {
                    shutdown.fire()
                }
                return CommandResult(status: 0, output: Data(networkSetup.run(command.arguments).utf8))
            })
            let cli = CLIHarness(commands: commands, shutdown: shutdown)

            try await Start.parse(["--system-proxy"]).run(in: cli.environment)

            #expect(cli.commands.calls.last == "networksetup -setsecurewebproxystate Wi-Fi off")
            #expect(!cli.files.paths.contains(cli.supportFile("system-proxy-backup.json")))
            #expect(cli.engine.calls == ["start any", "stop"])
        }

        private func failing(_ argument: String) -> CLIHarness {
            let networkSetup = NetworkSetupSpy()
            return CLIHarness(commands: CommandRunnerSpy(respond: { command in
                let failed = command.arguments[0] == argument
                return CommandResult(status: failed ? 1 : 0, output: Data(networkSetup.run(command.arguments).utf8))
            }))
        }

        @Test
        func aSystemProxyThatFailsHalfwayIsPutBackAndTheEngineStopped() async throws {
            let cli = failing("-setsecurewebproxy")

            await #expect(throws: (any Error).self) { try await StartCommandTests.run(["--system-proxy"], in: cli) }

            #expect(cli.commands.calls.contains("networksetup -setwebproxystate Wi-Fi off"))
            #expect(cli.commands.calls.last == "networksetup -setsecurewebproxystate Wi-Fi off")
            #expect(!cli.files.paths.contains(cli.supportFile("system-proxy-backup.json")))
            #expect(cli.engine.calls == ["start any", "stop"])
        }

        @Test
        func aSystemProxyThatFailsBeforeChangingAnythingStillStopsTheEngine() async throws {
            let cli = failing("-listallnetworkservices")

            await #expect(throws: (any Error).self) { try await StartCommandTests.run(["--system-proxy"], in: cli) }

            #expect(!cli.commands.calls.contains { $0.contains("-set") })
            #expect(cli.engine.calls == ["start any", "stop"])
        }

        @Test
        func withoutTheFlagTheSystemProxyIsLeftAlone() async throws {
            let cli = CLIHarness()
            try await StartCommandTests.run([], in: cli)
            #expect(cli.commands.commands.isEmpty)
        }

        @Test
        func theSessionIsSavedAsHARAndCSV() async throws {
            let cli = CLIHarness()
            try await StartCommandTests.run(["--har", "~/s.har", "--csv", "/tmp/s.csv"], in: cli) {
                let flow = cli.engine.store.begin(.fixture(path: "/saved"))
                cli.engine.store.update(flow.id) { $0.response = .fixture(); $0.state = .completed }
            }
            let flows = cli.engine.store.all
            #expect(flows.count == 1)
            let har = try #require(cli.files.contents(of: "/Users/me/s.har"))
            #expect(try HAR.flows(from: har).map(\.request.url) == ["https://api.example.com/saved"])
            #expect(cli.files.contents(of: "/tmp/s.csv") == CSVExporter.export(flows))
            #expect(cli.printed.suffix(2) == ["Saved ~/s.har", "Saved /tmp/s.csv"])
        }

        @Test
        func aSessionThatCannotBeSavedIsReportedAndFailsTheCommand() async throws {
            let cli = CLIHarness()
            cli.files.fail(.writeAtomically)
            await #expect(throws: ExitCode.failure) {
                try await StartCommandTests.run(["--har", "/tmp/s.har", "--csv", "/tmp/s.csv"], in: cli)
            }
            #expect(!cli.printed.contains { $0.hasPrefix("Saved") })
            #expect(cli.printedToErrorOutput.count == 2)
            #expect(cli.printedToErrorOutput.allSatisfy { $0.hasPrefix("Could not save /tmp/s.") })
            #expect(cli.engine.calls.last == "stop")
        }

        @Test
        func aSecondCtrlCDuringShutdownDoesNotShutDownAgain() async throws {
            let cli = CLIHarness()
            try await StartCommandTests.run(["--csv", "/tmp/s.csv"], in: cli, ctrlC: 2)
            #expect(cli.engine.calls == ["start any", "stop"])
            #expect(cli.printed.filter { $0.hasPrefix("Saved") } == ["Saved /tmp/s.csv"])
        }

        @Test
        func withoutExportsNothingIsWritten() async throws {
            let cli = CLIHarness()
            try await StartCommandTests.run([], in: cli)
            #expect(cli.files.paths.isEmpty)
            #expect(!cli.printed.contains { $0.hasPrefix("Saved") })
        }
    }
}
