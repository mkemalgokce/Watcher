import Foundation

/// What was negotiated with the client on one decrypted connection (shared by every request that arrives on it).
final class ConnectionDetails: @unchecked Sendable {
    private let lock = NSLock()
    private var tlsVersion: String?
    private var alpn: String?
    private var handshakeDone = false

    func record(tlsVersion: String?, alpn: String) {
        lock.withLock { self.tlsVersion = tlsVersion; self.alpn = alpn; handshakeDone = true }
    }

    var isHandshakeDone: Bool {
        lock.withLock { handshakeDone }
    }

    /// `TLS 1.3 · h2`, or nil for plain HTTP.
    var summary: String? {
        lock.withLock {
            let parts = [tlsVersion, alpn].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
}
