import Testing
import WatcherTestSupport

/// The shipped binary starts, listens, and leaves cleanly on Ctrl-C.
@Suite(.timeLimit(.minutes(1)), .tags(.smoke, .e2e))
struct StartCommandSmokeTests {
    @Test
    func theBinaryListensOnAFreePortAndExitsCleanlyOnCtrlC() async throws {
        try await withTemporaryDirectory(prefix: "watcher-smoke") { home in
            let cli = try WatcherCLIProcess(
                binary: WatcherCLIBinary.locate(),
                arguments: ["start", "--port", "0"],
                home: home.url
            )
            try cli.run()

            let port = try await cli.listeningPort()
            try await cli.interrupt()

            #expect(port > 0)
            #expect(cli.terminationStatus == 0)
        }
    }
}
