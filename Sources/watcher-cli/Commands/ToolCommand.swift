import ArgumentParser
import Foundation
import WatcherCore

struct Tool: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Switch a debugging tool on or off.")

    enum State: String, ExpressibleByArgument { case on, off }

    @Argument(help: "One of: \(ToolName.allCases.map(\.rawValue).joined(separator: ", ")).") var tool: ToolName
    @Argument var state: State

    func run() throws {
        let store = SettingsStore(url: WatcherPaths.supportDirectory.appendingPathComponent("settings.json"))
        try store.update { tool.set(state == .on, in: &$0) }
        print("\(tool.rawValue): \(state.rawValue)")
    }
}
