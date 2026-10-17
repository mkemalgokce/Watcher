import Foundation

public struct MapLocalRule: ToolRule {
    public enum Source: Codable, Equatable, Sendable {
        case file(String)
        /// Serves `<directory>/<request path after the pattern's static prefix>`.
        case directory(String)
    }

    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    public var source: Source
    public var delayMilliseconds: Int

    public init(
        name: String = "",
        isEnabled: Bool = true,
        matching: MatchingRule,
        source: Source,
        delayMilliseconds: Int = 0
    ) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching
        self.source = source; self.delayMilliseconds = delayMilliseconds
    }
}
