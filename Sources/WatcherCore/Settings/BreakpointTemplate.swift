/// A canned response a held breakpoint can be turned into with one click.
public struct BreakpointTemplate: Codable, Equatable, Sendable {
    public var name: String
    public var status: Int
    public var headers: [Header]
    public var body: String

    public init(name: String, status: Int, headers: [Header] = [], body: String = "") {
        self.name = name; self.status = status; self.headers = headers; self.body = body
    }

    private static func error(_ status: Int, _ name: String, _ code: String, extra: [Header] = []) -> BreakpointTemplate {
        BreakpointTemplate(name: "\(status) \(name)", status: status, headers: [Header("Content-Type", "application/json")] + extra, body: #"{"error":"\#(code)"}"#)
    }

    public static let builtIn = [
        error(401, "Unauthorized", "unauthorized"), error(404, "Not Found", "not_found"), error(429, "Too Many Requests", "too_many_requests", extra: [Header("Retry-After", "60")]),
        error(500, "Internal Server Error", "internal_error"), error(503, "Service Unavailable", "service_unavailable", extra: [Header("Retry-After", "30")]),
    ]
}

public extension WatcherSettings {
    var allBreakpointTemplates: [BreakpointTemplate] {
        BreakpointTemplate.builtIn + breakpointTemplates
    }
}
