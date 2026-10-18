import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CharlesConverterTests {
    private let charles = URL(fileURLWithPath: "/Apps/Charles")
    private let session = URL(fileURLWithPath: "/s/a.chls")
    private let output = "/fake-tmp/1.har"
    private let files: FileAccessFake

    init() {
        files = FileAccessFake(executables: ["/Apps/Charles"])
    }

    private func convert(_ spy: CommandRunnerSpy) async throws -> [Flow] {
        try await CharlesConverter.flows(from: session, charles: charles, runner: spy.runner, files: files.access)
    }

    private func spy(status: Int32 = 0, log: String = "", writes har: Data?) -> CommandRunnerSpy {
        CommandRunnerSpy(result: CommandResult(status: status, output: Data(log.utf8))) { [files, output] _ in
            if let har {
                files.write(har, to: output)
            }
        }
    }

    @Test
    func charlesConvertsTheSessionToATemporaryHARThatIsReadAndRemoved() async throws {
        let har = try HAR.export([Flow.fixture(request: .fixture(path: "/converted"))])
        let spy = spy(writes: har)
        let flows = try await convert(spy)
        #expect(flows.map(\.request.path) == ["/converted"])
        #expect(spy.commands == [Command(
            executable: charles, arguments: ["convert", "/s/a.chls", output], mergesErrorOutput: true
        )])
        #expect(files.paths.isEmpty)
    }

    @Test(arguments: [(Int32(1), true), (0, false), (2, false)])
    func aFailedConversionReportsCharlesOutputAndLeavesNoFile(status: Int32, writesFile: Bool) async {
        let error = await #expect(throws: CharlesConverter.ConversionError.self) {
            try await convert(spy(status: status, log: "bad file", writes: writesFile ? Data("{}".utf8) : nil))
        }
        #expect(error.map { "\($0)" } == "Charles could not convert the file: bad file")
        #expect(files.paths.isEmpty)
    }

    @Test
    func charlesThatCannotStartIsReported() async {
        await #expect(throws: CocoaError.self) {
            try await convert(CommandRunnerSpy(failure: CocoaError(.executableNotLoadable)))
        }
    }

    @Test
    func aMissingCharlesInstallIsReportedWithoutRunningAnything() async {
        let spy = CommandRunnerSpy()
        let error = await #expect(throws: CharlesConverter.ConversionError.self) {
            _ = try await CharlesConverter.flows(
                from: session,
                charles: URL(fileURLWithPath: "/nonexistent/Charles"),
                runner: spy.runner,
                files: files.access
            )
        }
        #expect(error.map { "\($0)" }?.contains("not found") == true)
        #expect(spy.commands.isEmpty)
    }
}
