import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct WatcherCLITests {
    @Test
    func noArgumentsRunsStart() throws {
        #expect(try WatcherCLI.parseAsRoot([]) is Start)
    }

    @Test(arguments: [
        ("start", "Start"), ("mcp", "Mcp"), ("cert", "Cert"), ("install-simulator-cert", "SimulatorCert"),
        ("android", "AndroidCommand"), ("tool", "Tool"), ("rules", "Rules"), ("proxy", "SystemProxyCommand"),
    ])
    func eachSubcommandNameRunsItsCommand(name: String, type: String) throws {
        let arguments = name == "tool" ? [name, "map-local", "on"] : name == "proxy" ? [name, "on"] : [name]
        let command = try WatcherCLI.parseAsRoot(arguments)
        #expect(String(describing: Swift.type(of: command)) == type)
    }

    @Test
    func helpListsEverySubcommand() {
        let help = WatcherCLI.helpMessage()
        for name in ["start", "mcp", "cert", "install-simulator-cert", "android", "tool", "rules", "proxy"] {
            #expect(help.contains(name), "\(name) missing from: \(help)")
        }
    }

    @Test(arguments: [["bogus"], ["start", "--bogus"], ["tool", "teleport", "on"], ["proxy", "sideways"]])
    func unknownArgumentsFailWithTheUsageExitCode(arguments: [String]) {
        let error = #expect(throws: (any Error).self) { try WatcherCLI.parseAsRoot(arguments) }
        #expect(error.map(WatcherCLI.exitCode(for:)) == .validationFailure)
    }
}
