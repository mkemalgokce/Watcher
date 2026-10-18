public struct BreakpointRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    public var onRequest: Bool
    public var onResponse: Bool

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule, onRequest: Bool = true, onResponse: Bool = true) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching
        self.onRequest = onRequest; self.onResponse = onResponse
    }
}
