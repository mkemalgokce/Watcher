import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ClientProcessTests {
    private static let lsofOutput = "p501\ncCurl Tool\nn127.0.0.1:54321->127.0.0.1:9090\n"
        + "p777\ncwatcher-cli\nn127.0.0.1:9090->127.0.0.1:54321\n"

    private func identity(port: Int, runner: CommandRunner, paths: [Int32: String] = [:]) -> ClientIdentity? {
        ClientProcess.identity(forLocalPort: port, runner: runner) { paths[$0] }
    }

    @Test
    func parsesThePidAndCommandOfTheProgramOwningTheClientEnd() {
        let curl = ClientProcess.Owner(pid: 501, command: "Curl Tool")
        #expect(ClientProcess.parse(Self.lsofOutput, port: 54321) == curl)
        #expect(ClientProcess.parse(Self.lsofOutput, port: 1111) == nil)
        let ipv6 = ClientProcess.parse("p12\ncx\nn[::1]:5->[::1]:9\n", port: 5)
        #expect(ipv6 == ClientProcess.Owner(pid: 12, command: "x"))
        let lan = ClientProcess.parse("p9\ncy\nn192.168.1.5:7->192.168.1.5:9090\n", port: 7)
        #expect(lan == ClientProcess.Owner(pid: 9, command: "y"), "a client that used the Mac's own LAN address")
        #expect(ClientProcess.parse("p9\ncy\nn192.168.1.5:9090->192.168.1.5:7\n", port: 7) == nil, "the server end")
        #expect(ClientProcess.parse("cx\nn127.0.0.1:5->127.0.0.1:9\n", port: 5) == nil, "no pid, no owner")
    }

    @Test
    func classifiesTheOwnerByItsExecutablePath() {
        let spy = CommandRunnerSpy(result: CommandResult(status: 0, output: Data(Self.lsofOutput.utf8)))
        #expect(
            identity(port: 54321, runner: spy.runner, paths: [501: "/usr/bin/curl"])
                == ClientIdentity(app: "Curl Tool", process: "Curl Tool", kind: .tool, bundlePath: nil)
        )
    }

    @Test
    func anOwnerWhosePathCannotBeReadIsAService() {
        let spy = CommandRunnerSpy(result: CommandResult(status: 0, output: Data(Self.lsofOutput.utf8)))
        #expect(identity(port: 54321, runner: spy.runner)?.kind == .service)
    }

    @Test
    func aPortNobodyOwnsHasNoIdentity() {
        let spy = CommandRunnerSpy(result: CommandResult(status: 0, output: Data(Self.lsofOutput.utf8)))
        #expect(identity(port: 1111, runner: spy.runner) == nil)
    }

    @Test
    func asksLsofForEstablishedTCPConnectionsOnThePortInFieldFormWithinATimeLimit() {
        let spy = CommandRunnerSpy()
        _ = identity(port: 54321, runner: spy.runner)
        #expect(spy.commands == [Command(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "+c", "0", "-iTCP:54321", "-sTCP:ESTABLISHED", "-Fpcn"],
            timeout: 5
        )])
    }

    @Test
    func lsofThatCannotStartGivesNoIdentity() {
        let spy = CommandRunnerSpy(failure: CocoaError(.fileNoSuchFile))
        #expect(identity(port: 54321, runner: spy.runner) == nil)
    }

    @Test
    func theLivePathLookupReadsThisProcessExecutable() {
        let path = ClientProcess.executablePath(ofPid: ProcessInfo.processInfo.processIdentifier)
        #expect(path?.hasPrefix("/") == true)
        #expect(ClientProcess.executablePath(ofPid: -1) == nil)
    }
}
