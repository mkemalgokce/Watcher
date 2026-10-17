import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.integration, .network, .externalTool))
struct ClientAppAttributionTests {
    @Test(.enabled(if: ExternalTool.curl.isAvailable, "needs curl"))
    func requestsAreAttributedToTheProgramThatSentThemAndCanBeBlockedByIt() async throws {
        try await withHarness { harness in
            #expect(try curl(through: harness).hasPrefix("GET /by-app"))
            #expect(harness.engine.store.all.first?.request.clientApp == "curl")

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
        let process = Process()
        process.executableURL = try ExternalTool.curl.require()
        process.arguments = [
            "-s", "-m", "10", "-x", "http://127.0.0.1:\(harness.proxyPort)", "\(harness.originURL)/by-app",
        ]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        return String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
