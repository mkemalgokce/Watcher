import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct StartCommandTests {
    @Test
    func defaultsUseTheStoredPortAndChangeNothingElse() throws {
        let start = try Start.parse([])
        #expect(start.port == nil)
        #expect(!start.noDecrypt)
        #expect(start.har == nil)
        #expect(start.csv == nil)
        #expect(!start.systemProxy)
    }

    @Test
    func readsEveryOption() throws {
        let arguments = ["--port", "0", "--no-decrypt", "--har", "~/x.har", "--csv", "y.csv", "--system-proxy"]
        let start = try Start.parse(arguments)
        #expect(start.port == 0)
        #expect(start.noDecrypt)
        #expect(start.har == "~/x.har")
        #expect(start.csv == "y.csv")
        #expect(start.systemProxy)
    }

    @Test(arguments: [["--port"], ["--port", "eighty"], ["--har"]])
    func rejectsAMissingOrMalformedValue(arguments: [String]) {
        #expect(throws: (any Error).self) { try Start.parse(arguments) }
    }
}
