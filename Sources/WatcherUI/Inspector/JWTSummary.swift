import Foundation
import WatcherCore

/// The JSON Web Tokens an exchange carries, and how they stand at `now`. Only headers are searched: that is where
/// tokens travel, and it keeps the inspector header instant for large bodies.
struct JWTSummary {
    let tokens: [JWT]
    let now: Date

    init(flow: Flow, now: Date) {
        let headers = flow.request.headers + (flow.response?.headers ?? [])
        tokens = JWT.find(in: headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n"))
        self.now = now
    }

    var title: String {
        tokens.count == 1 ? "JWT" : "\(tokens.count) JWTs"
    }

    var anyExpired: Bool {
        tokens.contains { $0.isExpired(at: now) }
    }

    var help: String {
        "Carries \(anyExpired ? "an expired" : "a") JSON Web Token. Click to decode it."
    }

    /// "Expired 2 hours ago" or "Expires in 5 minutes"; nil for a token without an expiry.
    func expiry(of token: JWT) -> (text: String, isExpired: Bool)? {
        guard let expires = token.expiresAt else { return nil }
        let relative = RelativeDateTimeFormatter().localizedString(for: expires, relativeTo: now)
        let expired = token.isExpired(at: now)
        return (expired ? "Expired \(relative)" : "Expires \(relative)", expired)
    }
}
