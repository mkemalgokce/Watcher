import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.integration, .network))
struct WatcherEngineTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    @Test
    func pausedRecordingStillForwardsAndTheSessionLimitKeepsTheNewest() async throws {
        try await withHarness(configure: { $0.maxFlows = 3 }) { harness in
            harness.engine.isRecording = false
            let paused = try await harness.get("/paused")
            #expect(paused.status == 200, "traffic still flows while recording is paused")
            #expect(harness.engine.store.all.isEmpty)

            harness.engine.isRecording = true
            for number in 1 ... 5 {
                _ = try await harness.get("/r\(number)")
            }
            #expect(
                harness.engine.store.all.map(\.request.path) == ["/r3", "/r4", "/r5"],
                "only the newest three are kept"
            )
        }
    }

    @Test
    func theSuggestedReversePortAvoidsPortsUsedByRules() throws {
        let engine = try WatcherEngine(directory: directory.url)
        let first = try #require(engine.suggestReversePort())
        try engine.settings.update { $0.reverseProxy.rules = [ReverseProxyRule(localPort: first, remoteHost: "a.com")] }
        #expect(engine.suggestReversePort() != first)
    }
}
