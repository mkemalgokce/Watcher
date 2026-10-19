import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network, .externalTool))
struct ClientAppAttributionTests {
    @Test(.enabled(if: ExternalTool.curl.isAvailable, "needs curl"))
    func requestsAreAttributedToTheProgramThatSentThemAndCanBeBlockedByIt() async throws {
        try await withHarness(clientApp: ClientProcess.identity(forLocalPort:)) { harness in
            #expect(try curl(through: harness).hasPrefix("GET /by-app"))
            let request = try #require(harness.engine.store.all.first?.request)
            #expect(request.clientApp == "curl" && request.clientProcess == "curl")
            #expect(request.clientKind == .tool, "curl is a command line tool, not an app or a system service")

            try await harness.reconfigure {
                $0.blockList = RuleSet(isEnabled: true, rules: [
                    BlockRule(matching: MatchingRule(pattern: "*", app: "curl")),
                ])
            }
            #expect(try curl(through: harness) == "Blocked by Watcher")
            let other = try await harness.get("/not-curl")
            #expect(other.status == 200, "only curl is blocked, not this test process")
        }
    }

    private func curl(through harness: Harness) throws -> String {
        try ExternalTool.curl.run([
            "-s", "-m", "10", "-x", "http://127.0.0.1:\(harness.proxyPort)", "\(harness.originURL)/by-app",
        ]).text
    }
}
