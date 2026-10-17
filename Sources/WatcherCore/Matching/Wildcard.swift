import Foundation

/// Case-insensitive glob: `*` matches any run of characters, `?` matches exactly one.
public struct Wildcard: Sendable {
    private let regex: NSRegularExpression?

    public init(_ pattern: String) {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        regex = try? NSRegularExpression(pattern: "^\(escaped)$", options: [.caseInsensitive])
    }

    public func matches(_ text: String) -> Bool {
        regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

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

public struct HostFilter: Sendable {
    public var include: HostList
    public var exclude: HostList

    public init(include: [String] = ["*"], exclude: [String] = []) {
        self.include = HostList(include); self.exclude = HostList(exclude)
    }

    public func allows(_ host: String) -> Bool {
        include.matches(host) && !exclude.matches(host)
    }
}
