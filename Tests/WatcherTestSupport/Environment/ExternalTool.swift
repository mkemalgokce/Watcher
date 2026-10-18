import Foundation
import WatcherCore

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
    /// and standard output; standard error is dropped. A tool still running after `timeout` is terminated.
    public func run(_ arguments: [String], input: Data = Data(), timeout: TimeInterval = 30) throws -> ToolOutput {
        let command = try Command(executable: require(), arguments: arguments, input: input, timeout: timeout)
        do {
            let result = try LiveCommandRunner.run(command)
            return ToolOutput(status: result.status, data: result.output)
        } catch { throw TestSupportError("\(name) could not start: \(error)") }
    }
}
