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
    private var contexts: [String: NIOSSLContext] = [:]
    private var _leafValidityDays = 365
    private var _keyLog: NIOSSLKeyLogCallback?

    public struct Unavailable: Error, CustomStringConvertible { public var description: String {
        "No root certificate available"
    } }

    public var certificateDER: Data {
        (try? Data(certificate.serializeAsPEM().derBytes)) ?? Data()
    }

    public var certificatePEM: String {
        (try? certificate.serializeAsPEM().pemString) ?? ""
    }

    /// Loads the CA from `directory`, creating and persisting it on first use.
    public init(directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let keyURL = directory.appendingPathComponent("watcher-ca.key.pem")
        let certURL = directory.appendingPathComponent("watcher-ca.pem")
        certificateURL = certURL
        let name = try DistinguishedName {
            CommonName("Watcher Root CA")
            OrganizationName("Watcher")
        }
        self.name = name

        if fm.fileExists(atPath: keyURL.path), fm.fileExists(atPath: certURL.path) {
            key = try P256.Signing.PrivateKey(pemRepresentation: String(contentsOf: keyURL, encoding: .utf8))
            certificate = try Certificate(pemEncoded: String(contentsOf: certURL, encoding: .utf8))
        } else {
            let key = P256.Signing.PrivateKey()
            let now = Date()
            certificate = try Certificate(
                version: .v3, serialNumber: .init(),
                publicKey: .init(key.publicKey),
                notValidBefore: now.addingTimeInterval(-3600),
                notValidAfter: now.addingTimeInterval(60 * 60 * 24 * 365 * 10),
                issuer: name, subject: name,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: Certificate.Extensions {
                    Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                    Critical(KeyUsage(keyCertSign: true, cRLSign: true))
                    SubjectKeyIdentifier(keyIdentifier: ArraySlice(Insecure.SHA1.hash(data: key.publicKey.derRepresentation)))
                },
                issuerPrivateKey: .init(key)
            )
            self.key = key
            try key.pemRepresentation.write(to: keyURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
            try certificate.serializeAsPEM().pemString.write(to: certURL, atomically: true, encoding: .utf8)
        }
        // Prefer the identifier stored in the certificate so leaf certificates always match the CA that is actually trusted.
        issuerKeyIdentifier = (try? certificate.extensions.subjectKeyIdentifier?.keyIdentifier)
            ?? ArraySlice(Insecure.SHA1.hash(data: key.publicKey.derRepresentation))
    }

    /// Validity of newly generated certificates, clamped to what Apple's TLS stack accepts (825 days).
    public func setLeafValidity(days: Int) {
        lock.withLock { _leafValidityDays = min(825, max(1, days)) }
    }

    /// Receives TLS session secrets for contexts created from now on; existing cached contexts are dropped so it takes effect.
    func setKeyLog(_ callback: NIOSSLKeyLogCallback?) {
        lock.withLock { _keyLog = callback; contexts.removeAll() }
    }

    /// TLS server context presenting a certificate for `host`, signed by this CA.
    public func serverContext(for host: String, offerHTTP2: Bool = true) throws -> NIOSSLContext {
        let cacheKey = "\(host)|\(offerHTTP2)"
        if let cached = lock.withLock({ contexts[cacheKey] }) {
            return cached
        }

        let leafKey = P256.Signing.PrivateKey()
        let leaf = try leafCertificate(for: host, key: leafKey)

        var configuration = try TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(NIOSSLCertificate(bytes: Array(leaf.serializeAsPEM().derBytes), format: .der))],
            privateKey: .privateKey(NIOSSLPrivateKey(bytes: Array(leafKey.derRepresentation), format: .der))
        )
        configuration.applicationProtocols = offerHTTP2 ? ["h2", "http/1.1"] : ["http/1.1"]
        configuration.keyLogCallback = lock.withLock { _keyLog }
        let context = try NIOSSLContext(configuration: configuration)
        lock.withLock { contexts[cacheKey] = context }
        return context
    }

    /// A one-year server certificate for `host`, signed by this CA.
    func leafCertificate(for host: String, key leafKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) throws -> Certificate {
        let now = Date()
        let san: GeneralName = IPv4Address(host) != nil ? .ipAddress(ASN1OctetString(contentBytes: ArraySlice(host.split(separator: ".").compactMap { UInt8($0) }))) : .dnsName(host)
        return try Certificate(
            version: .v3, serialNumber: .init(),
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
