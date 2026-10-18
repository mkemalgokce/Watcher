/// Only lets matching requests through; everything else is blocked.
struct AllowListTool: Tool {
    let name = "Allow List"
    var needsRequestBody: Bool {
        matchers.contains { $0.readsBody }
    }

    private let matchers: [RequestMatcher]

    init(rules: [AllowRule]) {
        matchers = rules.map { $0.matching.compile() }
    }

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        matchers.contains { $0.matches(request) } ? .forward : .block(hidden: false)
    }
}
