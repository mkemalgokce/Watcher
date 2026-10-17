import Foundation

/// A `MatchingRule` with its regex compiled once.
public struct RequestMatcher: Sendable {
    private let urlTest: @Sendable (String) -> Bool
    private let methods: Set<String>
    private let graphQLQueryName: String?
    private let appTest: Wildcard?
    /// True when matching needs the request body (GraphQL operation names).
    var readsBody: Bool {
        graphQLQueryName?.isEmpty == false
    }

    public init(_ rule: MatchingRule) {
        methods = Set(rule.methods.map { $0.uppercased() })
        graphQLQueryName = rule.graphQLQueryName
        appTest = rule.app.flatMap { $0.isEmpty ? nil : Wildcard($0) }
        let pattern = rule.pattern.isEmpty ? "*" : rule.pattern
        switch rule.mode {
        case .wildcard:
            let glob = Wildcard(rule.includeSubpaths && !pattern.hasSuffix("*") ? pattern + "*" : pattern)
            urlTest = { glob.matches($0) }
        case .regex:
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            urlTest = { regex?.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        }
    }

    public func matches(_ request: RequestRecord) -> Bool {
        if !methods.isEmpty, !methods.contains(request.method.uppercased()) {
            return false
        }
        if let appTest, !appTest.matches(request.clientApp ?? "") {
            return false
        }
        // Patterns may omit the scheme (`api.example.com/v1/*`) or spell out the port.
        let withoutScheme = request.url.drop { $0 != "/" }.dropFirst(2)
        let candidates = [request.url, String(withoutScheme), "\(request.host):\(request.port)\(request.path)"]
        guard candidates.contains(where: urlTest) else { return false }
        guard let name = graphQLQueryName, !name.isEmpty else { return true }
        return Self.graphQLOperation(in: request.body) == name
    }

    private static func graphQLOperation(in body: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["operationName"] as? String
    }
}
