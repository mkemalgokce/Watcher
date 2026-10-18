import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct CertCommandTests {
    @Test
    func takesNoArguments() {
        #expect(throws: (any Error).self) { try Cert.parse(["extra"]) }
    }

    @Test
    func printsThePathOfTheRootCertificateItCreated() throws {
        let cli = CLIHarness()
        try Cert().run(in: cli.environment)
        #expect(cli.printed == [cli.supportFile("watcher-ca.pem")])
        let created = [cli.supportFile("watcher-ca.pem"), cli.supportFile("watcher-ca.key.pem")]
        #expect(cli.files.paths.isSuperset(of: created))
    }

    @Test
    func printsNothingWhenTheCertificateCannotBeCreated() {
        let cli = CLIHarness()
        cli.files.fail(.createDirectory)
        #expect(throws: FileAccessFake.Failure(operation: .createDirectory)) { try Cert().run(in: cli.environment) }
        #expect(cli.printed.isEmpty)
    }
}
