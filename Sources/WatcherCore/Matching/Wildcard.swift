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
