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
}
