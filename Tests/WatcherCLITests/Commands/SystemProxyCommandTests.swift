import ArgumentParser
import Testing
@testable import watcher_cli
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
}
