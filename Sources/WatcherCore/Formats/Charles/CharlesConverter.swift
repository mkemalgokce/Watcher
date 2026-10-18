import Foundation

/// Opens binary Charles sessions (`.chls`, `.chlz`) by asking an installed Charles to convert them to HAR.
/// Without Charles installed these formats cannot be read.
/// shortcut: the `convert` invocation is unverified here (no Charles available); fix the arguments if your Charles version differs.
public enum CharlesConverter {
    public enum ConversionError: Error, CustomStringConvertible {
        case charlesNotFound(String)
        case failed(String)

        public var description: String {
            switch self {
            case let .charlesNotFound(path): "Charles Proxy not found at \(path); install it or export the session as JSON (.chlsj) from Charles."
            case let .failed(output): "Charles could not convert the file: \(output)"
            }
        }
    }

    public static let defaultExecutable = URL(fileURLWithPath: "/Applications/Charles.app/Contents/MacOS/Charles")

    public static func flows(
        from session: URL,
        charles: URL = defaultExecutable,
        runner: CommandRunner = LiveCommandRunner.run,
        files: FileAccess = .live
    ) async throws -> [Flow] {
        guard files.isExecutable(charles.path) else { throw ConversionError.charlesNotFound(charles.path) }
        let output = files.temporaryFile("har")
        defer { try? files.remove(output) }

        let result = try runner(Command(
            executable: charles,
            arguments: ["convert", session.path, output.path],
            mergesErrorOutput: true
        ))
        guard result.status == 0, files.fileExists(output.path) else { throw ConversionError.failed(result.text) }
        return try HAR.flows(from: files.read(output))
    }
}
