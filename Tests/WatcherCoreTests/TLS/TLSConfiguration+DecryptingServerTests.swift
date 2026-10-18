import Crypto
import Foundation
import NIOSSL
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct TLSConfigurationDecryptingServerTests {
    @Test(arguments: [(true, ["h2", "http/1.1"]), (false, ["http/1.1"])])
    func http2IsOfferedOnlyWhenAsked(offerHTTP2: Bool, protocols: [String]) throws {
        let authority = try CertificateAuthority(directory: URL(fileURLWithPath: "/ca"), files: FileAccessFake().access)
        let certificate = try NIOSSLCertificate(bytes: Array(authority.certificateDER), format: .der)
        let key = try NIOSSLPrivateKey(bytes: Array(P256.Signing.PrivateKey().derRepresentation), format: .der)
        let configuration = TLSConfiguration.decryptingServer(
            chain: [.certificate(certificate)],
            key: .privateKey(key),
            offerHTTP2: offerHTTP2,
            keyLog: nil
        )
        #expect(configuration.applicationProtocols == protocols)
        #expect(configuration.keyLogCallback == nil)
        #expect(configuration.certificateChain.count == 1)
    }
}
