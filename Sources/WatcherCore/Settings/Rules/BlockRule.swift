import Foundation

public struct BlockRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    /// When true the blocked request does not appear in the session list.
    public var hidesRequest: Bool

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule, hidesRequest: Bool = false) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching; self.hidesRequest = hidesRequest
    }
}
