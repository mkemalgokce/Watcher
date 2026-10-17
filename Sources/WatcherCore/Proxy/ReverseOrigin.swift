import Foundation

/// Fixed destination for a reverse-proxy listener.
struct ReverseOrigin: Sendable {
    let scheme: String
    let host: String
    let port: Int
    let preserveHost: Bool
}
