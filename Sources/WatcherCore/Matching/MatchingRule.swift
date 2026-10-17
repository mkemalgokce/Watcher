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
