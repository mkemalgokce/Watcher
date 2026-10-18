import Foundation
import WatcherCore
import WatcherTestSupport

/// One `watcher-cli` run to completion with its own `WATCHER_HOME`, for commands that exit by themselves.
enum WatcherCLIRun {
    static func run(
        _ arguments: [String],
        home: URL,
        input: String? = nil,
        includingErrorOutput: Bool = false
    ) throws -> CommandResult {
        let environment = ProcessInfo.processInfo.environment.merging(["WATCHER_HOME": home.path]) { $1 }
        let command = try Command(
            executable: WatcherCLIBinary.locate(),
            arguments: arguments,
            environment: environment,
            input: input.map { Data($0.utf8) },
            timeout: 30,
            mergesErrorOutput: includingErrorOutput
        )
        return try LiveCommandRunner.run(command)
    }
}
