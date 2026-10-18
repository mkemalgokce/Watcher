import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct ToolCommandTests {
    @Test(arguments: [("on", Tool.State.on), ("off", Tool.State.off)])
    func readsTheToolAndItsState(word: String, state: Tool.State) throws {
        let tool = try Tool.parse(["map-local", word])
        #expect(tool.tool == .mapLocal)
        #expect(tool.state == state)
    }

    @Test(arguments: [[], ["map-local"], ["map-local", "maybe"], ["teleport", "on"]])
    func rejectsAMissingOrUnknownValue(arguments: [String]) {
        #expect(throws: (any Error).self) { try Tool.parse(arguments) }
    }

    @Test
    func helpNamesEveryTool() {
        let help = Tool.helpMessage()
        for name in ToolName.allCases.map(\.rawValue) {
            #expect(help.contains(name), "\(name) missing from: \(help)")
        }
    }
}
