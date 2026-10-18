import Foundation

/// Redirects matching requests to another origin/path without the client noticing.
struct MapRemoteTool: Tool {
    let name = "Map Remote"
    var needsRequestBody: Bool {
        entries.contains { $0.matcher.readsBody }
    }

    private let entries: [(rule: MapRemoteRule, matcher: RequestMatcher)]

    init(rules: [MapRemoteRule]) {
        entries = rules.map { ($0, $0.matching.compile()) }
    }

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        guard let (rule, _) = entries.first(where: { $0.matcher.matches(request) }) else { return .forward }
        let target = rule.destination

        if let scheme = target.scheme, scheme != request.scheme {
            request.scheme = scheme
            if target.port == nil {
                request.port = RequestRecord.defaultPort(for: scheme)
            }
        }
        if let host = target.host {
            request.host = host
        }
        if let port = target.port {
            request.port = port
        }

        if target.path != nil || target.query != nil {
            let parts = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            let path = target.path ?? String(parts[0])
            let query = target.query ?? (parts.count > 1 ? String(parts[1]) : "")
            request.path = query.isEmpty ? path : "\(path)?\(query)"
        }

        if !rule.preserveHostHeader {
            request.headers.set("Host", request.usesDefaultPort ? request.host : "\(request.host):\(request.port)")
        }
        return .forward
    }
}
