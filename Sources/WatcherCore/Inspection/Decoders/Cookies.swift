import Foundation

public struct CookieEntry: Identifiable, Equatable, Sendable {
    public enum Source: String, Sendable { case request = "Cookie", response = "Set-Cookie" }

    /// The cookie's position among the flow's cookies, so the same flow gives the same ids.
    public let id: Int
    public let source: Source
    public let name: String
    public let value: String
    /// `Path=/`, `HttpOnly`, `Secure`, `SameSite=Lax`, … (response cookies only).
    public let attributes: [String]

    public var isSecure: Bool {
        attributes.contains { $0.caseInsensitiveCompare("Secure") == .orderedSame }
    }

    public var isHttpOnly: Bool {
        attributes.contains { $0.caseInsensitiveCompare("HttpOnly") == .orderedSame }
    }

    public static func == (a: CookieEntry, b: CookieEntry) -> Bool {
        a.source == b.source && a.name == b.name && a.value == b.value && a.attributes == b.attributes
    }
}

public enum Cookies {
    /// Cookies a request sent and a response set.
    public static func entries(for flow: Flow) -> [CookieEntry] {
        var result: [CookieEntry] = []
        for header in flow.request.headers where header.name.caseInsensitiveCompare("Cookie") == .orderedSame {
            for pair in header.value.split(separator: ";") {
                let (name, value) = split(String(pair))
                if !name.isEmpty {
                    result.append(CookieEntry(
                        id: result.count, source: .request, name: name, value: value, attributes: []
                    ))
                }
            }
        }
        for header in flow.response?.headers ?? [] where header.name.caseInsensitiveCompare("Set-Cookie") == .orderedSame {
            let parts = header.value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = parts.first else { continue }
            let (name, value) = split(first)
            if !name.isEmpty {
                result.append(CookieEntry(
                    id: result.count, source: .response, name: name, value: value, attributes: Array(parts.dropFirst())
                ))
            }
        }
        return result
    }

    private static func split(_ pair: String) -> (String, String) {
        let trimmed = pair.trimmingCharacters(in: .whitespaces)
        guard let equals = trimmed.firstIndex(of: "=") else { return (trimmed, "") }
        return (String(trimmed[..<equals]), String(trimmed[trimmed.index(after: equals)...]))
    }
}
