/// Which message type a request/response body is, per URL pattern.
public struct ProtobufRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    /// Fully qualified names such as `demo.User`; empty leaves that side to the schema-less decoder.
    public var requestType: String
    public var responseType: String

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule, requestType: String = "", responseType: String = "") {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching
        self.requestType = requestType; self.responseType = responseType
    }
}
