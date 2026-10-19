import ArgumentParser
import WatcherCore

extension ToolKind: ExpressibleByArgument {}

struct Tool: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Switch a debugging tool on or off.")

    enum State: String, ExpressibleByArgument { case on, off }

    @Argument(help: "One of: \(ToolKind.allCases.map(\.rawValue).joined(separator: ", ")).") var tool: ToolKind
    @Argument var state: State

    func run() throws {
        try run(in: .live)
    }

    func run(in environment: CLIEnvironment) throws {
        try environment.settings.update { $0[keyPath: tool.switchPath] = state == .on }
        environment.output("\(tool.rawValue): \(state.rawValue)")
    }
}
