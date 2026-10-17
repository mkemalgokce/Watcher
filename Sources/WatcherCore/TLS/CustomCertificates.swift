import Foundation
import NIOSSL

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
