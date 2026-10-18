import Foundation

/// A command-line program some tests drive, found at the places it is installed on a Mac.
public struct ExternalTool: Sendable {
    public static let python3 = ExternalTool(name: "python3", candidates: ["/usr/bin/python3"])
    public static let curl = ExternalTool(name: "curl", candidates: ["/usr/bin/curl"])
    public static let openssl = ExternalTool(name: "openssl", candidates: ["/usr/bin/openssl"])
    public static let shell = ExternalTool(name: "sh", candidates: ["/bin/sh"])
    // swiftlint:disable:next identifier_name
    public static let jq = ExternalTool(name: "jq", candidates: [
        "/opt/homebrew/bin/jq",
        "/usr/local/bin/jq",
        "/usr/bin/jq",
    ])
    public static let adb = ExternalTool(name: "adb", candidates: [
        "/opt/homebrew/bin/adb",
        "/usr/local/bin/adb",
        NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
    ])

    public let name: String
    public let candidates: [String]

    public init(name: String, candidates: [String]) {
        self.name = name
        self.candidates = candidates
    }

    public var url: URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    public var isAvailable: Bool {
        url != nil
    }

    public func require() throws -> URL {
        guard let url else {
            throw TestSupportError("\(name) is not installed (looked in \(candidates.joined(separator: ", ")))")
        }
        return url
    }

    /// Runs the tool to the end with `arguments`, feeding it `input` on standard input, and returns its exit status
    /// and standard output; standard error is dropped.
    public func run(_ arguments: [String], input: Data = Data()) throws -> ToolOutput {
        let process = Process()
        process.executableURL = try require()
        process.arguments = arguments
        let output = Pipe(), stdin = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = stdin
        do { try process.run() } catch { throw TestSupportError("\(name) could not start: \(error)") }
        let writer = stdin.fileHandleForWriting
        DispatchQueue.global().async {
            writer.write(input)
            try? writer.close()
        }
        // Read before waiting: a tool that fills the pipe blocks until someone reads it, and would never exit.
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ToolOutput(status: process.terminationStatus, data: printed)
    }
}
