import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct JQTests {
    private let json = Data(#"{"a":1}"#.utf8)
    private let homebrew = "/opt/homebrew/bin/jq"

    private func run(_ query: String, spy: CommandRunnerSpy, executables: Set<String>? = nil) -> String? {
        let files = FileAccessFake(executables: executables ?? [homebrew])
        return JQ.run(query, on: json, timeout: 2, runner: spy.runner, files: files.access)
    }

    @Test
    func theQueryRunsWithoutOptionsInputOrEnvironment() {
        let spy = CommandRunnerSpy(result: CommandResult(status: 0, output: Data("1\n".utf8)))
        #expect(run("  .a ", spy: spy) == "1\n")
        #expect(spy.commands == [Command(
            executable: URL(fileURLWithPath: homebrew),
            arguments: ["-M", ".a"],
            environment: [:],
            input: json,
            timeout: 2
        )])
    }

    @Test
    func theFirstInstalledCandidateIsUsed() {
        let spy = CommandRunnerSpy()
        _ = run(".a", spy: spy, executables: ["/usr/bin/jq", "/usr/local/bin/jq"])
        #expect(spy.commands.map(\.executable.path) == ["/usr/local/bin/jq"])
    }

    @Test(arguments: ["", "   ", "-n", " --help"])
    func emptyQueriesAndOptionsAreNeverRun(query: String) {
        let spy = CommandRunnerSpy()
        #expect(run(query, spy: spy) == nil)
        #expect(spy.commands.isEmpty)
    }

    @Test
    func withoutJQNothingRuns() {
        let spy = CommandRunnerSpy()
        #expect(run(".a", spy: spy, executables: []) == nil)
        #expect(spy.commands.isEmpty)
    }

    @Test(arguments: [Int32(1), 5, 15])
    func aFailedRunGivesNoOutput(status: Int32) {
        let spy = CommandRunnerSpy(result: CommandResult(status: status, output: Data("partial".utf8)))
        #expect(run(".a", spy: spy) == nil)
    }

    @Test
    func aProgramThatCannotStartGivesNoOutput() {
        #expect(run(".a", spy: CommandRunnerSpy(failure: CocoaError(.executableNotLoadable))) == nil)
    }
}
