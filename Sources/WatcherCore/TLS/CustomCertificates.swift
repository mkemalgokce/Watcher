import Foundation
import NIOSSL

/// Certificates supplied by the user as PKCS#12 files: a server identity Watcher presents for a host
/// (instead of a generated one) or a client identity it presents to an upstream that demands mutual TLS.
public struct CustomCertificateRule: ToolRule {
    public enum Role: String, Codable, Sendable { case server, client }

    public var name: String
    public var isEnabled: Bool
    public var folder: String?
    /// Host pattern (`*.example.com`).
    public var host: String
    public var role: Role
    public var p12Path: String
    public var passphrase: String

    public init(name: String = "", isEnabled: Bool = true, host: String, role: Role, p12Path: String, passphrase: String = "") {
        self.name = name; self.isEnabled = isEnabled; self.host = host; self.role = role; self.p12Path = p12Path; self.passphrase = passphrase
    }
}

enum CustomCertificates {
    static func bundle(_ rule: CustomCertificateRule) throws -> NIOSSLPKCS12Bundle {
        try NIOSSLPKCS12Bundle(file: (rule.p12Path as NSString).expandingTildeInPath, passphrase: Array(rule.passphrase.utf8))
    }

    static func serverContext(_ rule: CustomCertificateRule, offerHTTP2: Bool = true, keyLog: NIOSSLKeyLogCallback? = nil) throws -> NIOSSLContext {
        let identity = try bundle(rule)
        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: identity.certificateChain.map { .certificate($0) }, privateKey: .privateKey(identity.privateKey)
        )
        configuration.applicationProtocols = offerHTTP2 ? ["h2", "http/1.1"] : ["http/1.1"]
        configuration.keyLogCallback = keyLog
        return try NIOSSLContext(configuration: configuration)
    }

    static func applyClientIdentity(_ rule: CustomCertificateRule, to configuration: inout TLSConfiguration) throws {
        let identity = try bundle(rule)
        configuration.certificateChain = identity.certificateChain.map { .certificate($0) }
        configuration.privateKey = .privateKey(identity.privateKey)
    }
}
