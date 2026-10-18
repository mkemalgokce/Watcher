import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SimulatorCertCommandTests {
    @Test(arguments: [([], "booted"), (["--device", "all"], "all"), (["--device", "ABC-123"], "ABC-123")])
    func deviceDefaultsToTheBootedSimulator(arguments: [String], device: String) throws {
        #expect(try SimulatorCert.parse(arguments).device == device)
    }

    @Test(arguments: ["booted", "all", "ABC-123"])
    func addsTheRootCertificateToTheSimulatorKeychain(device: String) throws {
        let cli = CLIHarness()
        try SimulatorCert.parse(["--device", device]).run(in: cli.environment)
        #expect(cli.commands.commands == [Command(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "keychain", device, "add-root-cert", cli.supportFile("watcher-ca.pem")],
            mergesErrorOutput: true
        )])
        #expect(cli.files.paths.contains(cli.supportFile("watcher-ca.pem")))
        #expect(cli.printed == ["Installed in \(device)"])
    }

    @Test
    func reportsWhatSimctlPrintedWhenItFails() throws {
        let failing = CommandRunnerSpy(result: CommandResult(status: 1, output: Data("No devices".utf8)))
        let cli = CLIHarness(commands: failing)
        let command = try SimulatorCert.parse([])
        #expect(throws: CommandFailure(
            description: "xcrun simctl keychain booted add-root-cert \(cli.supportFile("watcher-ca.pem")): No devices"
        )) { try command.run(in: cli.environment) }
        #expect(cli.printed.isEmpty)
    }

    @Test(arguments: ["", "a b", "x;rm"])
    func refusesAnInvalidDeviceWithoutRunningSimctl(device: String) throws {
        let cli = CLIHarness()
        let command = try SimulatorCert.parse(["--device", device])
        #expect(throws: CommandFailure(description: "Invalid simulator: \(device)")) {
            try command.run(in: cli.environment)
        }
        #expect(cli.commands.commands.isEmpty)
        #expect(cli.printed.isEmpty)
    }

    @Test
    func neverRunsSimctlWhenTheRootCertificateCannotBeCreated() throws {
        let cli = CLIHarness()
        cli.files.fail(.createDirectory)
        let command = try SimulatorCert.parse([])
        #expect(throws: FileAccessFake.Failure(operation: .createDirectory)) { try command.run(in: cli.environment) }
        #expect(cli.commands.commands.isEmpty)
        #expect(cli.printed.isEmpty)
    }
}
