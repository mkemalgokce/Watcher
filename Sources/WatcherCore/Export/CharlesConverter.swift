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

    public static func flows(from session: URL, charles: URL = defaultExecutable) async throws -> [Flow] {
        guard FileManager.default.isExecutableFile(atPath: charles.path) else { throw ConversionError.charlesNotFound(charles.path) }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).har")
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = charles
        process.arguments = ["convert", session.path, output.path]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else { throw ConversionError.failed(log) }
        return try HAR.flows(from: Data(contentsOf: output))
    }
}
