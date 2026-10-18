import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SystemProxyCommandTests {
    @Test(arguments: [(["on"], SystemProxyCommand.State.on, 9090), (["off", "--port", "8888"], .off, 8888)])
    func readsTheStateAndPort(arguments: [String], state: SystemProxyCommand.State, port: Int) throws {
        let command = try SystemProxyCommand.parse(arguments)
        #expect(command.state == state)
        #expect(command.port == port)
    }

    @Test(arguments: [[], ["sideways"]])
    func requiresOnOrOff(arguments: [String]) {
        #expect(throws: (any Error).self) { try SystemProxyCommand.parse(arguments) }
    }

    @Test
    func onSavesTheUsersProxyThenPointsEveryServiceAtWatcher() throws {
        let cli = Self.harness()
        try SystemProxyCommand.parse(["on", "--port", "8888"]).run(in: cli.environment)
        #expect(cli.commands.calls == [
            "networksetup -listallnetworkservices",
            "networksetup -getwebproxy Wi-Fi",
            "networksetup -getsecurewebproxy Wi-Fi",
            "networksetup -setwebproxy Wi-Fi 127.0.0.1 8888",
            "networksetup -setsecurewebproxy Wi-Fi 127.0.0.1 8888",
        ])
        #expect(cli.files.paths.contains(cli.supportFile("system-proxy-backup.json")))
        #expect(cli.printed == ["System proxy on"])
    }

    @Test
    func offPutsTheSavedProxyBackAndForgetsIt() throws {
        let cli = Self.harness()
        try SystemProxyCommand.parse(["on"]).run(in: cli.environment)
        try SystemProxyCommand.parse(["off"]).run(in: cli.environment)
        #expect(cli.commands.calls.suffix(3) == [
            "networksetup -listallnetworkservices",
            "networksetup -setwebproxystate Wi-Fi off",
            "networksetup -setsecurewebproxystate Wi-Fi off",
        ])
        #expect(!cli.files.paths.contains(cli.supportFile("system-proxy-backup.json")))
        #expect(cli.printed == ["System proxy on", "System proxy off"])
    }

    @Test(arguments: ["on", "off"])
    func aFailingNetworksetupIsReportedAndNothingIsPrinted(state: String) throws {
        let failing = CommandRunnerSpy(result: CommandResult(status: 14, output: Data("not allowed".utf8)))
        let cli = CLIHarness(commands: failing)
        let command = try SystemProxyCommand.parse([state])
        #expect(throws: CommandFailure(description: "networksetup -listallnetworkservices: not allowed")) {
            try command.run(in: cli.environment)
        }
        #expect(cli.printed.isEmpty)
    }

    private static func harness() -> CLIHarness {
        let networkSetup = NetworkSetupSpy()
        let commands = CommandRunnerSpy(respond: { command in
            CommandResult(status: 0, output: Data(networkSetup.run(command.arguments).utf8))
        })
        return CLIHarness(commands: commands)
    }
}
