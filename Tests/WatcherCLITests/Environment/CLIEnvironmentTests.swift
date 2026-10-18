import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CLIEnvironmentTests {
    @Test(arguments: [
        ("~", "/Users/me"), ("~/x.har", "/Users/me/x.har"), ("/tmp/s.har", "/tmp/s.har"),
        ("~/a/b.csv", "/Users/me/a/b.csv"),
    ])
    func aTildeInATypedPathMeansTheHomeFolder(typed: String, path: String) {
        #expect(CLIHarness().environment.url(forPath: typed).path == path)
    }

    @Test(arguments: [
        ("s.har", "/work/s.har"), ("./a/../b.csv", "/work/b.csv"), ("out/s.har", "/work/out/s.har"),
        ("../up.csv", "/up.csv"), ("~other/x", "/work/~other/x"), ("", "/work"), ("/tmp/../x", "/x"),
    ])
    func aRelativePathIsResolvedAgainstTheWorkingDirectory(typed: String, path: String) {
        #expect(CLIHarness().environment.url(forPath: typed).path == path)
    }

    @Test(arguments: [(["WATCHER_HOME": "/tmp/isolated"], "/tmp/isolated"), ([:], "/Users/me/.watcher")])
    func supportFilesLiveWhereWatcherHomeSays(variables: [String: String], directory: String) {
        var environment = CLIHarness().environment
        environment.variables = variables
        #expect(environment.supportDirectory.path == directory)
    }

    @Test
    func theLiveEnvironmentReadsTheProcessEnvironmentAndWorkingDirectory() {
        let live = CLIEnvironment.live
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #expect(live.variables == ProcessInfo.processInfo.environment)
        #expect(live.home == home)
        #expect(live.currentDirectory.path == FileManager.default.currentDirectoryPath)
        let variables = ProcessInfo.processInfo.environment
        #expect(live.supportDirectory == WatcherPaths.directory(environment: variables, home: home))
    }

    @Test
    func anEngineThatCannotOpenIsReportedOnStandardErrorWithAFailureExit() async {
        let cli = CLIHarness(opensEngine: false)
        await #expect(throws: ExitCode.failure) { try await cli.environment.startEngine(port: nil) { _ in } }
        #expect(cli.printedToErrorOutput == [
            "Cannot open Watcher's data in \(CLIHarness.supportDirectory): Failure(). Check the folder is readable.",
        ])
        #expect(cli.printed.isEmpty)
    }

    @Test
    func aProxyThatCannotStartIsReportedOnStandardErrorWithAFailureExit() async {
        let cli = CLIHarness(engine: { EngineFake(settings: $0, failsToStart: true) })
        await #expect(throws: ExitCode.failure) { try await cli.environment.startEngine(port: 8080) { _ in } }
        #expect(cli.printedToErrorOutput == [
            "Cannot start the proxy: Failure(). Another program may be using the port; try --port.",
        ])
        #expect(cli.printed.isEmpty)
    }
}
