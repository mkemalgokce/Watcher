import Foundation
import WatcherCore

/// Records every command and answers with `result`, or throws `failure` as if the program could not start.
/// `onRun` runs before answering, e.g. to write the file a real program would leave behind.
public final class CommandRunnerSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Command] = []
    private let result: CommandResult
    private let failure: (any Error)?
    private let onRun: @Sendable (Command) -> Void

    public init(
        result: CommandResult = CommandResult(status: 0, output: Data()),
        failure: (any Error)? = nil,
        onRun: @escaping @Sendable (Command) -> Void = { _ in }
    ) {
        self.result = result; self.failure = failure; self.onRun = onRun
    }

    public var commands: [Command] {
        lock.withLock { recorded }
    }

    public var runner: CommandRunner {
        { [self] command in
            lock.withLock { recorded.append(command) }
            onRun(command)
            if let failure {
                throw failure
            }
            return result
        }
    }
}
