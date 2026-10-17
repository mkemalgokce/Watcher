import Foundation

/// Rejects requests matching any rule with 403.
struct BlockListTool: Tool {
    let name = "Block List"
    var needsRequestBody: Bool {
        entries.contains { $0.matcher.readsBody }
    }

    private let entries: [(matcher: RequestMatcher, hidden: Bool)]

    init(rules: [BlockRule]) {
        entries = rules.map { ($0.matching.compile(), $0.hidesRequest) }
    }

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        guard let hit = entries.first(where: { $0.matcher.matches(request) }) else { return .forward }
        return .block(hidden: hit.hidden)
    }
}

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

/// Forces fresh responses by stripping validators and disabling caches.
struct NoCachingTool: Tool {
    let name = "No Caching"

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        request = request.droppingCacheValidators()
        return .forward
    }
}
