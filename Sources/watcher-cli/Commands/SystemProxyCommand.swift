import ArgumentParser
import Foundation
import WatcherCore

struct SystemProxyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "proxy", abstract: "Turn the macOS system HTTP(S) proxy on or off.")

    enum State: String, ExpressibleByArgument { case on, off }

    @Argument var state: State
    @Option var port = 9090

    func run() throws {
        switch state {
        case .on: try SystemProxy.enable(port: port)
        case .off: try SystemProxy.disable()
        }
        print("System proxy \(state.rawValue)")
    }
}
