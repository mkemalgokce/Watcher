public struct ScriptRule: ToolRule {
    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    public var matching: MatchingRule
    /// JavaScript defining `onRequest(context, url, request)` and/or `onResponse(context, url, request, response)`.
    public var source: String

    public init(name: String = "", isEnabled: Bool = true, matching: MatchingRule, source: String = ScriptRule.template) {
        self.name = name; self.isEnabled = isEnabled; self.matching = matching; self.source = source
    }

    public static let template = """
    async function onRequest(context, url, request) {
      // request.headers["X-Watcher"] = "1";
      // request.queries["debug"] = "true";
      return request;
    }

    async function onResponse(context, url, request, response) {
      // response.statusCode = 500;
      // response.headers["Content-Type"] = "application/json";
      // response.bodyFilePath = "~/Desktop/mock.json";
      return response;
    }
    """
}
