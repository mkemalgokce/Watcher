import Foundation

/// Which requests a tool applies to: URL pattern, optional methods and optional GraphQL operation.
public struct MatchingRule: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case wildcard, regex }

    public var pattern: String
    public var mode: Mode
    /// Empty means any method.
    public var methods: [String]
    public var includeSubpaths: Bool
    public var graphQLQueryName: String?
    /// Only requests from programs whose name matches this pattern (e.g. `Google Chrome*`); nil means any program.
    public var app: String?

    public init(
        pattern: String = "*",
        mode: Mode = .wildcard,
        methods: [String] = [],
        includeSubpaths: Bool = false,
        graphQLQueryName: String? = nil,
        app: String? = nil
    ) {
        self.pattern = pattern; self.mode = mode; self.methods = methods
        self.includeSubpaths = includeSubpaths; self.graphQLQueryName = graphQLQueryName; self.app = app
    }

    public func compile() -> RequestMatcher {
        RequestMatcher(self)
    }
}

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
