import Foundation
import WatcherCore

/// One `watcher-cli` run to completion with its own `WATCHER_HOME`, for commands that exit by themselves.
enum WatcherCLIRun {
    static func run(
        _ arguments: [String],
        home: URL,
        input: String? = nil,
        includingErrorOutput: Bool = false
    ) throws -> CommandResult {
        let command = try Command(
            executable: WatcherCLIBinary.locate(),
            arguments: arguments,
            environment: WatcherCLIBinary.environment(home: home),
            input: input.map { Data($0.utf8) },
            timeout: 30,
            mergesErrorOutput: includingErrorOutput
        )
        return try LiveCommandRunner.run(command)
    }
}
