import Foundation
import NIOSSL
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CustomCertificatesTests {
    private let files = FileAccessFake(files: ["/certs/id.p12": Data("not a p12".utf8)])
    private let rule = CustomCertificateRule(host: "a.test", role: .server, p12Path: "/certs/id.p12", passphrase: "x")

    @Test
    func theIdentityIsReadThroughFileAccess() {
        files.fail(.read)
        #expect(throws: FileAccessFake.Failure(operation: .read)) {
            try CustomCertificates.serverContext(rule, files: files.access)
        }
        var configuration = TLSConfiguration.makeClientConfiguration()
        #expect(throws: FileAccessFake.Failure(operation: .read)) {
            try CustomCertificates.applyClientIdentity(rule, to: &configuration, files: files.access)
        }
    }

    @Test
    func bytesThatAreNotAP12AreRefused() {
        #expect(throws: (any Error).self) { try CustomCertificates.serverContext(rule, files: files.access) }
    }
}
