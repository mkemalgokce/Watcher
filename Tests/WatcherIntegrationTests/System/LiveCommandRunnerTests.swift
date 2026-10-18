import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration))
struct LiveCommandRunnerTests {
    private func run(
        _ path: String,
        _ arguments: [String] = [],
        configure: (inout Command) -> Void = { _ in }
    ) throws -> CommandResult {
        var command = Command(executable: URL(fileURLWithPath: path), arguments: arguments)
        configure(&command)
        return try LiveCommandRunner.run(command)
    }

    @Test
    func inputIsPassedThroughAndOutputCollected() throws {
        let result = try run("/bin/cat") { $0.input = Data("hello".utf8) }
        #expect(result == CommandResult(status: 0, output: Data("hello".utf8)))
    }

    @Test
    func theExitStatusIsReported() throws {
        #expect(try run("/usr/bin/false").status == 1)
    }

    @Test(arguments: [(true, "out\nerr\n"), (false, "out\n")])
    func errorOutputIsMergedOnlyWhenAsked(merges: Bool, output: String) throws {
        let result = try run("/bin/sh", ["-c", "echo out; echo err >&2"]) { $0.mergesErrorOutput = merges }
        #expect(String(bytes: result.output, encoding: .utf8) == output)
    }

    @Test
    func anEmptyEnvironmentHidesThisProcesssVariables() throws {
        #expect(try run("/usr/bin/env") { $0.environment = [:] }.output.isEmpty)
    }

    @Test(.tags(.timing))
    func aProgramRunningPastItsTimeoutIsTerminated() throws {
        let started = Date()
        let result = try run("/bin/sleep", ["10"]) { $0.timeout = 0.2 }
        #expect(result.status != 0)
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test
    func aMissingProgramThrows() {
        #expect(throws: (any Error).self) { try run("/nonexistent/program") }
    }

    @Test
    func largeInputAndOutputDoNotDeadlock() throws {
        let input = Data(repeating: UInt8(ascii: "x"), count: 1024 * 1024)
        let result = try run("/bin/cat") { $0.input = input; $0.timeout = 30 }
        #expect(result == CommandResult(status: 0, output: input))
    }

    @Test
    func aProgramExitingBeforeReadingItsInputIsNotAFatalSignal() throws {
        let result = try run("/bin/sh", ["-c", "exit 3"]) { $0.input = Data(count: 1024 * 1024) }
        #expect(result.status == 3)
    }
}
