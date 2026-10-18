struct BreakpointTool: Tool {
    let name = "Breakpoint"
    var needsRequestBody: Bool {
        entries.contains { $0.rule.onRequest || $0.matcher.readsBody }
    }

    var inspectsResponses: Bool {
        entries.contains { $0.rule.onResponse }
    }

    private let entries: [(rule: BreakpointRule, matcher: RequestMatcher)]
    private let center: BreakpointCenter

    init(rules: [BreakpointRule], center: BreakpointCenter) {
        entries = rules.map { ($0, $0.matching.compile()) }
        self.center = center
    }

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        guard entries.contains(where: { $0.rule.onRequest && $0.matcher.matches(request) }) else { return .forward }
        switch await center.hold(phase: .request, request: request) {
        case let .proceed(edited, _): request = edited; return .forward
        case .abort: return .respond(ProxyServer.message(502, "Request aborted at a Watcher breakpoint"))
        }
    }

    func intercept(response: inout ResponseRecord, for request: RequestRecord) async {
        guard entries.contains(where: { $0.rule.onResponse && $0.matcher.matches(request) }) else { return }
        switch await center.hold(phase: .response, request: request, response: response) {
        case let .proceed(_, edited): if let edited {
                response = edited
            }
        case .abort: response = ProxyServer.message(502, "Response aborted at a Watcher breakpoint")
        }
    }
}
