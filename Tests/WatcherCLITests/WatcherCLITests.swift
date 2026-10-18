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

    @Test(arguments: WatcherCLI.subcommands)
    func eachSubcommandNameRunsItsCommand(name: String, type: String) throws {
        let arguments = name == "tool" ? [name, "map-local", "on"] : name == "proxy" ? [name, "on"] : [name]
        let command = try WatcherCLI.parseAsRoot(arguments)
        #expect(String(describing: Swift.type(of: command)) == type)
    }

    @Test
    func theSubcommandTableCoversEverySubcommand() {
        let registered = WatcherCLI.configuration.subcommands.map { String(describing: $0) }
        #expect(registered == WatcherCLI.subcommands.map(\.type))
    }

    @Test
    func helpListsEverySubcommand() {
        let help = WatcherCLI.helpMessage()
        for name in WatcherCLI.subcommandNames {
            #expect(help.contains(name), "\(name) missing from: \(help)")
        }
    }

    @Test(arguments: [["bogus"], ["start", "--bogus"], ["tool", "teleport", "on"], ["proxy", "sideways"]])
    func unknownArgumentsFailWithTheUsageExitCode(arguments: [String]) {
        let error = #expect(throws: (any Error).self) { try WatcherCLI.parseAsRoot(arguments) }
        #expect(error.map(WatcherCLI.exitCode(for:)) == .validationFailure)
    }
}
