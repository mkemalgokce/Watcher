import Foundation
import Testing
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CommandRunnerTests {
    private let command = Command(executable: URL(fileURLWithPath: "/usr/bin/tool"), arguments: ["a", "b"])

    @Test
    func aSuccessfulRunAnswersWithItsText() throws {
        let spy = CommandRunnerSpy(result: CommandResult(status: 0, output: Data("done\n".utf8)))
        #expect(try command.checkedOutput(using: spy.runner) == "done\n")
        #expect(spy.commands == [command])
    }

    @Test
    func aNonZeroExitThrowsWithTheProgramItsArgumentsAndItsOutput() {
        let spy = CommandRunnerSpy(result: CommandResult(status: 3, output: Data("denied".utf8)))
        #expect(throws: CommandFailure(description: "tool a b: denied")) {
            try command.checkedOutput(using: spy.runner)
        }
    }

    @Test
    func aProgramThatCannotStartPassesItsErrorOn() {
        let spy = CommandRunnerSpy(failure: CocoaError(.fileNoSuchFile))
        #expect(throws: CocoaError.self) { try command.checkedOutput(using: spy.runner) }
    }
}
