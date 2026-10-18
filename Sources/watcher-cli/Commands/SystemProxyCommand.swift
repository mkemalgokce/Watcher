import ArgumentParser
import Foundation
import WatcherCore

struct SystemProxyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "proxy", abstract: "Turn the macOS system HTTP(S) proxy on or off.")

    enum State: String, ExpressibleByArgument { case on, off }

    @Argument var state: State
    @Option var port = 9090

    func run() throws {
        try run(in: .live)
    }

    func run(in environment: CLIEnvironment) throws {
        switch state {
        case .on: try environment.systemProxy.enable(port: port)
        case .off: try environment.systemProxy.disable()
        }
        environment.output("System proxy \(state.rawValue)")
    }
}
