import Foundation

/// A command-line program some tests drive, found at the places it is installed on a Mac.
public struct ExternalTool: Sendable {
    public static let python3 = ExternalTool(name: "python3", candidates: ["/usr/bin/python3"])
    public static let curl = ExternalTool(name: "curl", candidates: ["/usr/bin/curl"])
    public static let openssl = ExternalTool(name: "openssl", candidates: ["/usr/bin/openssl"])
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
}
