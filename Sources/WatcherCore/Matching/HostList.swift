import Foundation

/// Host patterns such as `*.example.com`, with optional exclusions.
public struct HostList: Sendable {
    private let wildcards: [Wildcard]
    public let patterns: [String]

    public init(_ patterns: [String]) {
        self.patterns = patterns
        wildcards = patterns.map(Wildcard.init)
    }

    public func matches(_ host: String) -> Bool {
        wildcards.contains { $0.matches(host) }
    }
}
