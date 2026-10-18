import Foundation
import NIOSSL

enum CustomCertificates {
    static func bundle(_ rule: CustomCertificateRule, files: FileAccess) throws -> NIOSSLPKCS12Bundle {
        let data = try files.read(URL(fileURLWithPath: (rule.p12Path as NSString).expandingTildeInPath))
        return try NIOSSLPKCS12Bundle(buffer: Array(data), passphrase: Array(rule.passphrase.utf8))
    }

    static func serverContext(
        _ rule: CustomCertificateRule,
        offerHTTP2: Bool = true,
        keyLog: NIOSSLKeyLogCallback? = nil,
        files: FileAccess = .live
    ) throws -> NIOSSLContext {
        let identity = try bundle(rule, files: files)
        let configuration = TLSConfiguration.decryptingServer(
            chain: identity.certificateChain.map { .certificate($0) },
            key: .privateKey(identity.privateKey),
            offerHTTP2: offerHTTP2,
            keyLog: keyLog
        )
        return try NIOSSLContext(configuration: configuration)
    }

    static func applyClientIdentity(
        _ rule: CustomCertificateRule,
        to configuration: inout TLSConfiguration,
        files: FileAccess = .live
    ) throws {
        let identity = try bundle(rule, files: files)
        configuration.certificateChain = identity.certificateChain.map { .certificate($0) }
        configuration.privateKey = .privateKey(identity.privateKey)
    }
}
