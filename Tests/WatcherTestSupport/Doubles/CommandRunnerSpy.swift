import Foundation
import WatcherCore

/// Records every command and answers with `result`, or throws `failure` as if the program could not start.
/// `onRun` runs before answering, e.g. to write the file a real program would leave behind; `respond` answers each
/// command by what it asks instead, e.g. when one spy stands in for several programs.
public final class CommandRunnerSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Command] = []
    private let respond: @Sendable (Command) throws -> CommandResult

    public convenience init(
        result: CommandResult = CommandResult(status: 0, output: Data()),
        failure: (any Error)? = nil,
        onRun: @escaping @Sendable (Command) -> Void = { _ in }
    ) {
        self.init(respond: { command in
            onRun(command)
            if let failure {
                throw failure
            }
            return result
        })
    }

    public init(respond: @escaping @Sendable (Command) throws -> CommandResult) {
        self.respond = respond
    }

    /// Answers like `networksetup` through `spy`, exiting 1 for the subcommand named `failing`.
    public static func networkSetup(
        _ spy: NetworkSetupSpy = NetworkSetupSpy(),
        failing subcommand: String? = nil,
        onRun: @escaping @Sendable (Command) -> Void = { _ in }
    ) -> CommandRunnerSpy {
        CommandRunnerSpy(respond: { command in
            onRun(command)
            let failed = command.arguments.first == subcommand
            return CommandResult(status: failed ? 1 : 0, output: Data(spy.run(command.arguments).utf8))
        })
    }

    public var commands: [Command] {
        lock.withLock { recorded }
    }

    /// Each command as one line, `program arg arg …`, for comparing whole sequences at a glance.
    public var calls: [String] {
        commands.map { ([$0.executable.lastPathComponent] + $0.arguments).joined(separator: " ") }
    }

    public var runner: CommandRunner {
        { [self] command in
            lock.withLock { recorded.append(command) }
            return try respond(command)
        }
    }
}
