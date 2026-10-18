import Crypto
import Foundation
import NIOSSL
import SwiftASN1
import X509

/// Root CA that signs on-the-fly leaf certificates for SSL Proxying.
public final class CertificateAuthority: @unchecked Sendable {
    public let certificate: Certificate
    /// The root certificate as a PEM file, for tools such as `curl --cacert`.
    public let certificateURL: URL
    private let key: P256.Signing.PrivateKey
    private let name: DistinguishedName
    private let issuerKeyIdentifier: ArraySlice<UInt8>
    private let lock = NSLock()
    private var contexts: [String: (context: NIOSSLContext, expires: Date)] = [:]
    private var _leafValidityDays = 365
    private var _keyLog: NIOSSLKeyLogCallback?
    private let now: @Sendable () -> Date

    public struct Unavailable: Error, CustomStringConvertible { public var description: String {
        "No root certificate available"
    } }

    /// Only one of the two files exists; replacing them would orphan the root the user already trusts.
    public struct Incomplete: Error, CustomStringConvertible {
        public let missing: String
        public var description: String {
            "The root certificate is incomplete: \(missing) is missing. "
                + "Restore it, or remove the other file to start over."
        }
    }

    public var certificateDER: Data {
        (try? Data(certificate.serializeAsPEM().derBytes)) ?? Data()
    }

    public var certificatePEM: String {
        (try? certificate.serializeAsPEM().pemString) ?? ""
    }

    /// Loads the CA from `directory`, creating and persisting it on first use.
    public init(directory: URL, files: FileAccess = .live, now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.now = now
        try files.createDirectory(directory)
        let keyURL = directory.appendingPathComponent("watcher-ca.key.pem")
        let certURL = directory.appendingPathComponent("watcher-ca.pem")
        certificateURL = certURL
        let name = try DistinguishedName {
            CommonName("Watcher Root CA")
            OrganizationName("Watcher")
        }
        self.name = name

        let hasKey = files.fileExists(keyURL.path), hasCertificate = files.fileExists(certURL.path)
        if hasKey != hasCertificate {
            throw Incomplete(missing: hasKey ? certURL.lastPathComponent : keyURL.lastPathComponent)
        }
        if hasKey {
            key = try P256.Signing.PrivateKey(pemRepresentation: Self.text(of: keyURL, files: files))
            certificate = try Certificate(pemEncoded: Self.text(of: certURL, files: files))
        } else {
            let key = P256.Signing.PrivateKey()
            certificate = try Self.makeRoot(key: key, name: name, now: now())
            self.key = key
            try files.writePrivately(Data(key.pemRepresentation.utf8), keyURL)
            try files.writeAtomically(Data(certificate.serializeAsPEM().pemString.utf8), certURL)
        }
        // Prefer the identifier stored in the certificate so leaf certificates always match the CA that is actually trusted.
        issuerKeyIdentifier = (try? certificate.extensions.subjectKeyIdentifier?.keyIdentifier)
            ?? ArraySlice(Insecure.SHA1.hash(data: key.publicKey.derRepresentation))
    }

    private static func text(of url: URL, files: FileAccess) throws -> String {
        guard let text = try String(bytes: files.read(url), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    /// A self-signed root valid for ten years from an hour ago.
    private static func makeRoot(
        key: P256.Signing.PrivateKey,
        name: DistinguishedName,
        now: Date
    ) throws -> Certificate {
        let keyIdentifier = ArraySlice(Insecure.SHA1.hash(data: key.publicKey.derRepresentation))
        return try Certificate(
            version: .v3, serialNumber: randomSerialNumber(),
            publicKey: .init(key.publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 365 * 10),
            issuer: name, subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                Critical(KeyUsage(keyCertSign: true, cRLSign: true))
                SubjectKeyIdentifier(keyIdentifier: keyIdentifier)
            },
            issuerPrivateKey: .init(key)
        )
    }

    /// Validity of newly generated certificates, clamped to what Apple's TLS stack accepts (825 days).
    public func setLeafValidity(days: Int) {
        lock.withLock {
            let clamped = min(825, max(1, days))
            if clamped != _leafValidityDays {
                _leafValidityDays = clamped; contexts.removeAll()
            }
        }
    }

    /// Receives TLS session secrets for contexts created from now on; existing cached contexts are dropped so it takes effect.
    func setKeyLog(_ callback: NIOSSLKeyLogCallback?) {
        lock.withLock { _keyLog = callback; contexts.removeAll() }
    }

    /// TLS server context presenting a certificate for `host`, signed by this CA.
    public func serverContext(for host: String, offerHTTP2: Bool = true) throws -> NIOSSLContext {
        let cacheKey = "\(host)|\(offerHTTP2)"
        if let cached = lock.withLock({ contexts[cacheKey] }), cached.expires > now() {
            return cached.context
        }

        let leafKey = P256.Signing.PrivateKey()
        let leaf = try leafCertificate(for: host, key: leafKey)

        let configuration = try TLSConfiguration.decryptingServer(
            chain: [.certificate(NIOSSLCertificate(bytes: Array(leaf.serializeAsPEM().derBytes), format: .der))],
            key: .privateKey(NIOSSLPrivateKey(bytes: Array(leafKey.derRepresentation), format: .der)),
            offerHTTP2: offerHTTP2,
            keyLog: lock.withLock { _keyLog }
        )
        let context = try NIOSSLContext(configuration: configuration)
        let expires = leaf.notValidAfter.addingTimeInterval(-Self.renewalMargin)
        lock.withLock { contexts[cacheKey] = (context, expires) }
        return context
    }

    /// Same 20 random bytes as `SerialNumber()`, whose zero-sized generator passed `inout` crashes ThreadSanitizer.
    private static func randomSerialNumber() -> Certificate.SerialNumber {
        Certificate.SerialNumber(bytes: (0 ..< 20).map { _ in UInt8.random(in: .min ... .max) })
    }

    private static func subjectName(for host: String) -> GeneralName {
        if IPv4Address(host) != nil {
            let octets = host.split(separator: ".").compactMap { UInt8($0) }
            return .ipAddress(ASN1OctetString(contentBytes: ArraySlice(octets)))
        }
        var address = in6_addr()
        if inet_pton(AF_INET6, host, &address) == 1 {
            let bytes = withUnsafeBytes(of: &address) { Array($0) }
            return .ipAddress(ASN1OctetString(contentBytes: ArraySlice(bytes)))
        }
        return .dnsName(host)
    }

    /// A cached leaf is replaced this long before it expires.
    private static let renewalMargin: TimeInterval = 3600

    /// A one-year server certificate for `host`, signed by this CA.
    func leafCertificate(for host: String, key leafKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) throws -> Certificate {
        let now = now()
        let san = Self.subjectName(for: host)
        return try Certificate(
            version: .v3, serialNumber: Self.randomSerialNumber(),
            publicKey: .init(leafKey.publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            // Apple rejects server certificates valid for more than 825 days.
            notValidAfter: now.addingTimeInterval(60 * 60 * 24 * Double(lock.withLock { _leafValidityDays })),
            issuer: name,
            subject: DistinguishedName { CommonName(host) },
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames([san])
                // Strict verifiers (OpenSSL 3 / Python 3.13) reject leaf certificates that do not name their issuer's key.
                SubjectKeyIdentifier(keyIdentifier: ArraySlice(Insecure.SHA1.hash(data: leafKey.publicKey.derRepresentation)))
                AuthorityKeyIdentifier(keyIdentifier: issuerKeyIdentifier)
            },
            issuerPrivateKey: .init(key)
        )
    }
}

/// Minimal dotted-quad check; avoids pulling in Network just for SAN selection.
private struct IPv4Address {
    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { return nil }
    }
}
