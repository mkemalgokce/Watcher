import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct ImportCharlesCommandTests {
    @Test(arguments: [(["charles.xml"], "append"), (["charles.xml", "--mode", "override"], "override")])
    func modeDefaultsToAppend(arguments: [String], mode: String) throws {
        let command = try ImportCharles.parse(arguments)
        #expect(command.path == "charles.xml")
        #expect(command.mode == mode)
    }
}
