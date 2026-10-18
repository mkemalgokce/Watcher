import Foundation

/// One run of an external program.
public struct Command: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    /// nil inherits this process's environment.
    public var environment: [String: String]?
    /// Written to the program's standard input, which is then closed.
    public var input: Data?
    /// The program is terminated after this long; nil waits for it to finish.
    public var timeout: TimeInterval?
    /// Error output joins `output` instead of being discarded.
    public var mergesErrorOutput: Bool

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = nil,
        mergesErrorOutput: Bool = false
    ) {
        self.executable = executable; self.arguments = arguments; self.environment = environment
        self.input = input; self.timeout = timeout; self.mergesErrorOutput = mergesErrorOutput
    }
}

public struct CommandResult: Equatable, Sendable {
    public var status: Int32
    public var output: Data

    public init(status: Int32, output: Data) {
        self.status = status; self.output = output
    }

    /// Bytes that are not UTF-8 become U+FFFD instead of losing the whole output.
    public var text: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: output, as: UTF8.self)
    }
}

/// Runs a command to completion; throws when it cannot be started.
public typealias CommandRunner = @Sendable (Command) throws -> CommandResult
