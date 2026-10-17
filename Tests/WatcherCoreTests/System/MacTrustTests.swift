import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MacTrustTests {
    @Test
    func installsTheRootThroughSecurityAndReportsFailure() throws {
        let calls = LockedBox<[[String]]>([])
        let trust = MacTrust(keychain: "/k") { path, args in
            #expect(path == "/usr/bin/security"); calls.mutate(args)
            return (args[0] == "find-certificate" ? 44 : 0, "")
        }
        #expect(!trust.isInstalled())
        try trust.install(certificate: URL(fileURLWithPath: "/tmp/ca.pem"))
        #expect(calls.value.last == ["add-trusted-cert", "-r", "trustRoot", "-k", "/k", "/tmp/ca.pem"])
        let failing = MacTrust(keychain: "/k") { _, _ in (1, "denied") }
        #expect(throws: (any Error).self) { try failing.install(certificate: URL(fileURLWithPath: "/x")) }
    }
}
