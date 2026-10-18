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
        ("::1", GeneralName.ipAddress(.init(contentBytes: zeros(15) + [1]))),
        ("fe80::1:2", GeneralName.ipAddress(.init(contentBytes: [0xFE, 0x80] + zeros(10) + [0, 1, 0, 2]))),
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

    @Test
    func aChangedValidityDropsTheCachedContextsButAnUnchangedOneKeepsThem() throws {
        let authority = try authority()
        let first = try authority.serverContext(for: "a.test")
        authority.setLeafValidity(days: 365)
        #expect(try authority.serverContext(for: "a.test") === first)
        authority.setLeafValidity(days: 30)
        #expect(try authority.serverContext(for: "a.test") !== first)
    }

    @Test
    func aCachedContextIsReplacedBeforeItsLeafExpires() throws {
        let clock = LockedBox(now)
        let authority = try CertificateAuthority(directory: directory, files: files.access, now: { clock.value })
        authority.setLeafValidity(days: 1)
        let first = try authority.serverContext(for: "a.test")
        clock.mutate { $0 = now.addingTimeInterval(3600) }
        #expect(try authority.serverContext(for: "a.test") === first)
        clock.mutate { $0 = now.addingTimeInterval(86400) }
        #expect(try authority.serverContext(for: "a.test") !== first)
    }

    @Test(arguments: [true, false])
    func onlyHalfOfASavedAuthorityIsReportedNotReplaced(keyRemains: Bool) throws {
        _ = try authority()
        let removed = keyRemains ? certificatePath : keyPath
        let kept = keyRemains ? keyPath : certificatePath
        files.remove(removed)
        let before = files.contents(of: kept)
        #expect(throws: CertificateAuthority.Incomplete.self) { try authority() }
        #expect(files.contents(of: kept) == before)
        #expect(files.contents(of: removed) == nil)
    }
}

private func zeros(_ count: Int) -> [UInt8] {
    [UInt8](repeating: 0, count: count)
}
