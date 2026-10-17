import Foundation

/// Hides secrets before captured traffic is shown to someone or something else (an AI agent over MCP, for instance).
public enum Redaction {
    public static let placeholder = "[redacted]"

    private static let sensitiveHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key", "api-key", "x-auth-token", "x-csrf-token", "x-xsrf-token",
    ]

    public static func redact(_ headers: [Header]) -> [Header] {
        headers.map { sensitiveHeaders.contains($0.name.lowercased()) ? Header($0.name, placeholder) : $0 }
    }

    public static func redact(_ request: RequestRecord) -> RequestRecord {
        var copy = request
        copy.headers = redact(request.headers)
        return copy
    }
}
