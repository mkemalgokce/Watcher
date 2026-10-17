import Foundation

public struct PreviewerRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    /// JavaScript defining `preview(message)`; `message` has `url`, `status`, `headers`, `body` (text or null) and `bodyBase64`.
    public var source: String

    public init(name: String = "Previewer", isEnabled: Bool = true, matching: MatchingRule, source: String = PreviewerRule.template) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching; self.source = source
    }

    public static let template = """
    function preview(message) {
      // Return a string, or any JSON value to have it pretty-printed.
      return atob(message.bodyBase64);
    }
    """
}
