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
