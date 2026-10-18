import Foundation

/// A system tool that ran but failed, described with what it printed.
public struct CommandFailure: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

public extension Command {
    /// Runs the command and answers with its text; a non-zero exit throws `CommandFailure` naming the call.
    func checkedOutput(using runner: CommandRunner) throws -> String {
        let result = try runner(self)
        guard result.status == 0 else {
            let call = ([executable.lastPathComponent] + arguments).joined(separator: " ")
            throw CommandFailure(description: "\(call): \(result.text)")
        }
        return result.text
    }
}
