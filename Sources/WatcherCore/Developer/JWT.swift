import Foundation

/// A JSON Web Token split into its readable parts. The signature is shown, never verified: Watcher has no key.
public struct JWT: Equatable, Sendable {
    public let raw: String
    public let header: String
    public let payload: String
    public let issuedAt: Date?
    public let expiresAt: Date?
    public let notBefore: Date?

    public func isExpired(at date: Date = Date()) -> Bool {
        expiresAt.map { $0 < date } ?? false
    }

    public init?(_ token: String) {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let headerData = Base64Finder.decode(String(parts[0])), let payloadData = Base64Finder.decode(String(parts[1])),
              let headerObject = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let payloadObject = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any], headerObject["alg"] != nil else { return nil }
        raw = token
        header = JSONFormatter.sortedKeys(headerData) ?? String(decoding: headerData, as: UTF8.self)
        payload = JSONFormatter.sortedKeys(payloadData) ?? String(decoding: payloadData, as: UTF8.self)
        func date(_ key: String) -> Date? {
            (payloadObject[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        }
        issuedAt = date("iat"); expiresAt = date("exp"); notBefore = date("nbf")
    }

    /// Every distinct token in `text` (headers, cookies, bodies).
    public static func find(in text: String) -> [JWT] {
        guard let regex = try? NSRegularExpression(pattern: #"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*"#) else { return [] }
        let ns = text as NSString
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let token = ns.substring(with: match.range)
            return seen.insert(token).inserted ? JWT(token) : nil
        }
    }
}
