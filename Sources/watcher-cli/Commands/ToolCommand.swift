import ArgumentParser
import Foundation
import WatcherCore

struct Tool: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Switch a debugging tool on or off.")

    enum State: String, ExpressibleByArgument { case on, off }

    @Argument(help: "One of: \(ToolName.allCases.map(\.rawValue).joined(separator: ", ")).") var tool: ToolName
    @Argument var state: State

    func run() throws {
        try run(in: .live)
    }

    func run(in environment: CLIEnvironment) throws {
        try environment.settings.update { tool.set(state == .on, in: &$0) }
        environment.output("\(tool.rawValue): \(state.rawValue)")
    }
}
