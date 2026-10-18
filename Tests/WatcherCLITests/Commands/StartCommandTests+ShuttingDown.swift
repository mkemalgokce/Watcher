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
            let networkSetup = NetworkSetupSpy()
            let commands = CommandRunnerSpy(respond: { command in
                CommandResult(status: 0, output: Data(networkSetup.run(command.arguments).utf8))
            })
            let cli = CLIHarness(commands: commands)
            let original = #"{"enabled":true,"server":"10.0.0.1","port":3128}"#
            let backup = #"{"Wi-Fi":{"web":\#(original),"secure":\#(original)}}"#
            cli.files.write(Data(backup.utf8), to: cli.supportFile("system-proxy-backup.json"))

            try await StartCommandTests.run(["--system-proxy"], in: cli)

            #expect(!cli.commands.calls.contains { $0.contains("-getwebproxy") })
            #expect(cli.commands.calls.suffix(4) == [
                "networksetup -setwebproxy Wi-Fi 10.0.0.1 3128",
                "networksetup -setwebproxystate Wi-Fi on",
                "networksetup -setsecurewebproxy Wi-Fi 10.0.0.1 3128",
                "networksetup -setsecurewebproxystate Wi-Fi on",
            ])
            #expect(!cli.files.paths.contains(cli.supportFile("system-proxy-backup.json")))
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
            let command = try Start.parse(["--har", "/tmp/s.har", "--csv", "/tmp/s.csv"])
            let running = Task { [environment = cli.environment] in try await command.run(in: environment) }
            #expect(await eventually(timeout: 30) { cli.shutdown.isAwaited })
            cli.shutdown.fire()
            await #expect(throws: ExitCode.failure) { try await running.value }
            #expect(!cli.printed.contains { $0.hasPrefix("Saved") })
            #expect(cli.printedToErrorOutput.count == 2)
            #expect(cli.printedToErrorOutput.allSatisfy { $0.hasPrefix("Could not save /tmp/s.") })
            #expect(cli.engine.calls.last == "stop")
        }

        @Test
        func aSecondCtrlCDuringShutdownDoesNotShutDownAgain() async throws {
            let cli = CLIHarness()
            let command = try Start.parse(["--csv", "/tmp/s.csv"])
            let running = Task { [environment = cli.environment] in try await command.run(in: environment) }
            #expect(await eventually(timeout: 30) { cli.shutdown.isAwaited })
            cli.shutdown.fire()
            cli.shutdown.fire()
            try await running.value
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
