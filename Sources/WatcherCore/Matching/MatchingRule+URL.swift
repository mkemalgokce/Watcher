import Foundation

public extension MatchingRule {
    /// This host and path with any query: anchored at both ends, so a look-alike name never matches. The root also
    /// matches a bare host.
    static func exactURL(host: String, path: String, methods: [String] = []) -> MatchingRule {
        let escapedPath = path.isEmpty || path == "/" ? "/?" : NSRegularExpression.escapedPattern(for: path)
        return MatchingRule(
            pattern: anchored(host: NSRegularExpression.escapedPattern(for: host), tail: escapedPath + #"(\?.*)?"#),
            mode: .regex,
            methods: methods
        )
    }

    /// Every URL on this host, and on its subdomains when asked.
    static func host(_ host: String, subdomains: Bool) -> MatchingRule {
        let name = (subdomains ? #"([^/?:]+\.)?"# : "") + NSRegularExpression.escapedPattern(for: host)
        return MatchingRule(pattern: anchored(host: name, tail: #"([/?].*)?"#), mode: .regex)
    }

    private static func anchored(host: String, tail: String) -> String {
        #"^([A-Za-z][A-Za-z0-9+.-]*://)?"# + host + #"(:\d+)?"# + tail + "$"
    }
}
