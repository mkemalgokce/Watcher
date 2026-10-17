import Foundation

public struct AllowRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching
    }
}
