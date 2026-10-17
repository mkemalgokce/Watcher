import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CertificateAuthorityTests {
    @Test
    func leafCertificatesNameTheirIssuerForStrictVerifiers() throws {
        let directory = try TemporaryDirectory(prefix: "watcher-ca")
        let authority = try CertificateAuthority(directory: directory.url)
        let caIdentifier = try #require(authority.certificate.extensions.subjectKeyIdentifier?.keyIdentifier)
        let leaf = try authority.leafCertificate(for: "example.com")
        #expect(try #require(leaf.extensions.authorityKeyIdentifier?.keyIdentifier) == caIdentifier)
        #expect(try leaf.extensions.subjectKeyIdentifier != nil)
        let reloaded = try CertificateAuthority(directory: directory.url)
        #expect(
            try reloaded.leafCertificate(for: "example.com")
                .extensions.authorityKeyIdentifier?.keyIdentifier == caIdentifier,
            "a CA reloaded from disk must keep issuing matching leaves"
        )
    }
}
