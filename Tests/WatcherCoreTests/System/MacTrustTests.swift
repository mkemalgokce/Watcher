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
            return (0, "")
        }
        try trust.install(certificate: URL(fileURLWithPath: "/tmp/ca.pem"))
        #expect(calls.value.last == ["add-trusted-cert", "-r", "trustRoot", "-k", "/k", "/tmp/ca.pem"])
        let failing = MacTrust(keychain: "/k") { _, _ in (1, "denied") }
        #expect(throws: (any Error).self) { try failing.install(certificate: URL(fileURLWithPath: "/x")) }
    }

    /// Another Watcher root of the same name (an older install) must not make a new certificate look trusted.
    @Test(arguments: [(Int32(0), true), (1, false)])
    func trustIsCheckedForThisCertificateFileNotByName(status: Int32, trusted: Bool) {
        let calls = LockedBox<[[String]]>([])
        let trust = MacTrust(keychain: "/k") { _, args in calls.mutate(args); return (status, "") }
        #expect(trust.isTrusted(certificate: URL(fileURLWithPath: "/home/.watcher/watcher-ca.pem")) == trusted)
        #expect(calls.value == [["verify-cert", "-c", "/home/.watcher/watcher-ca.pem", "-p", "basic", "-L", "-l"]])
    }

    @Test
    func trustIsNotClaimedWhenTheCheckCannotRun() {
        struct Missing: Error {}
        let trust = MacTrust(keychain: "/k") { _, _ in throw Missing() }
        #expect(!trust.isTrusted(certificate: URL(fileURLWithPath: "/ca.pem")))
    }

    @Test
    func removeDeletesTheNamedCertificateAndReportsFailure() throws {
        let calls = LockedBox<[[String]]>([])
        try MacTrust(keychain: "/k") { _, args in calls.mutate(args); return (0, "") }.remove()
        #expect(calls.value == [["delete-certificate", "-c", "Watcher Root CA", "/k"]])
        let failing = MacTrust(keychain: "/k") { _, _ in (44, "not found") }
        #expect(throws: CommandFailure(description: "security delete-certificate: not found")) { try failing.remove() }
    }

    @Test
    func theProcessRunnerAnswersWithStatusAndMergedOutput() throws {
        let spy = CommandRunnerSpy(result: CommandResult(status: 44, output: Data("missing".utf8)))
        let result = try MacTrust.process(using: spy.runner)("/usr/bin/security", ["find-certificate"])
        #expect(result.status == 44)
        #expect(result.output == "missing")
        #expect(spy.commands == [Command(
            executable: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["find-certificate"],
            mergesErrorOutput: true
        )])
    }
}
