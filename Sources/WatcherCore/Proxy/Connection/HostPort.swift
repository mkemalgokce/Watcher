import Foundation

/// A `host[:port]` as it appears in a CONNECT target or a Host header, with IPv6 literals in brackets.
struct HostPort: Equatable {
    let host: String
    let port: Int

    init(host: String, port: Int) {
        self.host = host; self.port = port
    }

    /// `host` without the brackets an IPv6 literal carries in a URL; Foundation's `URLComponents.host` keeps them on some macOS releases.
    static func unbracketed(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }

    /// Nil when no host is named or an explicit port is out of range; an absent, empty or non-numeric port becomes `defaultPort`.
    init?(_ text: String, defaultPort: Int) {
        let rest: Substring
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            host = String(text[text.index(after: text.startIndex) ..< close])
            rest = text[text.index(after: close)...]
        } else if text.filter({ $0 == ":" }).count > 1 {
            host = text
            rest = ""
        } else {
            let colon = text.firstIndex(of: ":") ?? text.endIndex
            host = String(text[..<colon])
            rest = text[colon...]
        }
        guard !host.isEmpty else { return nil }
        let digits = rest.dropFirst()
        let isNumber = !digits.isEmpty && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber)
        guard rest.hasPrefix(":"), isNumber else {
            port = defaultPort
            return
        }
        guard let value = Int(digits), (1 ... 65535).contains(value) else { return nil }
        port = value
    }
}
