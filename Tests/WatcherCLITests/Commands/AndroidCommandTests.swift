import ArgumentParser
import Testing
@testable import watcher_cli
import WatcherTestSupport

@Suite(.tags(.unit))
struct AndroidCommandTests {
    @Test
    func defaultsListDevicesForPort9090() throws {
        let android = try AndroidCommand.parse([])
        #expect(android.action == .list)
        #expect(android.serial == nil)
        #expect(android.port == 9090)
    }

    @Test(arguments: [
        ("list", AndroidCommand.Action.list), ("cert", .cert), ("proxy", .proxy), ("unproxy", .unproxy),
    ])
    func readsTheAction(word: String, action: AndroidCommand.Action) throws {
        let android = try AndroidCommand.parse([word, "--serial", "emulator-5554", "--port", "8888"])
        #expect(android.action == action)
        #expect(android.serial == "emulator-5554")
        #expect(android.port == 8888)
    }

    @Test(arguments: [["flash"], ["--port", "x"]])
    func rejectsAnUnknownActionOrMalformedPort(arguments: [String]) {
        #expect(throws: (any Error).self) { try AndroidCommand.parse(arguments) }
    }
}
