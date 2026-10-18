import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct McpCommandTests {
    @Test(arguments: [([], nil), (["--port", "0"], 0), (["--port", "8888"], 8888)] as [([String], Int?)])
    func portDefaultsToTheStoredOne(arguments: [String], port: Int?) throws {
        #expect(try Mcp.parse(arguments).port == port)
    }
}
