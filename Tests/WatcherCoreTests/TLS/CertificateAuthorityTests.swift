import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
import X509

@Suite(.tags(.unit))
struct CertificateAuthorityTests {
    private let directory = URL(fileURLWithPath: "/fake-home/.watcher")
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let files = FileAccessFake()
    private var keyPath: String {
        directory.appendingPathComponent("watcher-ca.key.pem").path
    }

    private var certificatePath: String {
        directory.appendingPathComponent("watcher-ca.pem").path
    }

    private func authority() throws -> CertificateAuthority {
        try CertificateAuthority(directory: directory, files: files.access, now: { [now] in now })
    }

    @Test
    func aNewAuthorityIsSavedWithAPrivateKeyOnlyTheUserCanRead() throws {
        let authority = try authority()
        #expect(files.folders.contains(directory.path))
        #expect(files.permissionHistory(of: keyPath) == [0o600])
        #expect(authority.certificateURL.path == certificatePath)
        #expect(files.contents(of: certificatePath) == Data(authority.certificatePEM.utf8))
        let keyWritten = try #require(files.access.modificationDate(keyPath))
        let certificateWritten = try #require(files.access.modificationDate(certificatePath))
        #expect(keyWritten < certificateWritten, "the key exists before the certificate that names it")
    }

    @Test
    func aSavedAuthorityIsLoadedBackInsteadOfReplaced() throws {
        let first = try authority()
        let second = try authority()
        #expect(second.certificate == first.certificate)
        let identifier = try #require(first.certificate.extensions.subjectKeyIdentifier?.keyIdentifier)
        let leaf = try second.leafCertificate(for: "example.com")
        #expect(
            try leaf.extensions.authorityKeyIdentifier?.keyIdentifier == identifier,
            "a CA reloaded from disk must keep issuing matching leaves"
        )
    }

    @Test
    func aDamagedKeyFileIsReported() throws {
        _ = try authority()
        files.write(Data("not a key".utf8), to: keyPath)
        #expect(throws: (any Error).self) { try authority() }
    }

    @Test(arguments: [FileAccessFake.Operation.createDirectory, .writePrivately, .writeAtomically])
    func aFolderOrFileThatCannotBeWrittenIsReported(_ operation: FileAccessFake.Operation) {
        files.fail(operation)
        #expect(throws: FileAccessFake.Failure(operation: operation)) { try authority() }
    }

    @Test
    func theRootIsValidFromAnHourAgoForTenYears() throws {
        let certificate = try authority().certificate
        #expect(certificate.notValidBefore == now.addingTimeInterval(-3600))
        #expect(certificate.notValidAfter == now.addingTimeInterval(60 * 60 * 24 * 365 * 10))
    }

    @Test
    func leafCertificatesNameTheirIssuerForStrictVerifiers() throws {
        let authority = try authority()
        let caIdentifier = try #require(authority.certificate.extensions.subjectKeyIdentifier?.keyIdentifier)
        let leaf = try authority.leafCertificate(for: "example.com")
        #expect(try #require(leaf.extensions.authorityKeyIdentifier?.keyIdentifier) == caIdentifier)
        #expect(try leaf.extensions.subjectKeyIdentifier != nil)
        #expect(leaf.issuer == authority.certificate.subject)
    }

    @Test(arguments: [(30, 30), (9999, 825), (0, 1)])
    func leafValidityFollowsTheSettingAndStaysUnderApplesLimit(setting: Int, days: Int) throws {
        let authority = try authority()
        authority.setLeafValidity(days: setting)
        let leaf = try authority.leafCertificate(for: "a.test")
        #expect(leaf.notValidBefore == now.addingTimeInterval(-3600))
        #expect(leaf.notValidAfter == now.addingTimeInterval(Double(days) * 86400))
    }

    @Test(arguments: [
        ("192.168.1.5", GeneralName.ipAddress(.init(contentBytes: [192, 168, 1, 5]))),
        ("api.example.com", GeneralName.dnsName("api.example.com")),
        ("1.2.3", GeneralName.dnsName("1.2.3")),
    ])
    func aLeafNamesItsHostAsAnAddressOrADomain(host: String, name: GeneralName) throws {
        let leaf = try authority().leafCertificate(for: host)
        #expect(try leaf.extensions.subjectAlternativeNames.map(Array.init) == [name])
    }

    @Test
    func serverContextsAreCachedPerHostUntilTheKeyLogChanges() throws {
        let authority = try authority()
        let first = try authority.serverContext(for: "a.test")
        #expect(try authority.serverContext(for: "a.test") === first)
        #expect(try authority.serverContext(for: "a.test", offerHTTP2: false) !== first)
        authority.setKeyLog(nil)
        #expect(try authority.serverContext(for: "a.test") !== first)
    }
}
