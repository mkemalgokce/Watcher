import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ClientProcessTests {
    private static let lsofOutput = "p501\ncCurl Tool\nn127.0.0.1:54321->127.0.0.1:9090\n"
        + "p777\ncwatcher-cli\nn127.0.0.1:9090->127.0.0.1:54321\n"

    @Test(arguments: [(54321, "Curl Tool"), (1111, nil)] as [(Int, String?)])
    func namesTheProgramOwningTheClientEndOfTheConnection(port: Int, name: String?) {
        let spy = CommandRunnerSpy(result: CommandResult(status: 0, output: Data(Self.lsofOutput.utf8)))
        #expect(ClientProcess.name(forLocalPort: port, runner: spy.runner) == name)
    }

    @Test
    func asksLsofForEstablishedTCPConnectionsOnThePortInFieldFormWithinATimeLimit() {
        let spy = CommandRunnerSpy()
        _ = ClientProcess.name(forLocalPort: 54321, runner: spy.runner)
        #expect(spy.commands == [Command(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "+c", "0", "-iTCP:54321", "-sTCP:ESTABLISHED", "-Fpcn"],
            timeout: 5
        )])
    }

    @Test
    func lsofThatCannotStartNamesNoProgram() {
        let spy = CommandRunnerSpy(failure: CocoaError(.fileNoSuchFile))
        #expect(ClientProcess.name(forLocalPort: 54321, runner: spy.runner) == nil)
    }
}
