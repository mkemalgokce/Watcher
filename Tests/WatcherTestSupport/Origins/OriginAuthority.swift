import Foundation
import NIOSSL
import WatcherCore

/// A certificate authority of the test's own, standing in for a public one: it signs the HTTPS origins' certificates,
/// and a client that trusts only its root reaches them and nothing else.
public struct OriginAuthority {
    private let authority: CertificateAuthority

    public init() throws {
        authority = try CertificateAuthority(
            directory: URL(fileURLWithPath: "/origin-ca"),
            files: FileAccessFake().access
        )
    }

    /// The certificate an origin presents for `host`, speaking HTTP/1.1 only.
    public func serverContext(for host: String) throws -> NIOSSLContext {
        try authority.serverContext(for: host, offerHTTP2: false)
    }

    /// Client settings that trust this authority's root alone.
    public var trust: TLSConfiguration {
        get throws {
            try Self.trusting(authority)
        }
    }

    /// Client settings that trust `authority`'s root alone, such as the root Watcher signs decrypted traffic with.
    public static func trusting(_ authority: CertificateAuthority) throws -> TLSConfiguration {
        var configuration = TLSConfiguration.makeClientConfiguration()
        let root = try NIOSSLCertificate(bytes: Array(authority.certificateDER), format: .der)
        configuration.trustRoots = .certificates([root])
        return configuration
    }
}
