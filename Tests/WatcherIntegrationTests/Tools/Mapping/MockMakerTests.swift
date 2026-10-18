import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct MockMakerTests {
    /// The rule, put in the engine, answers with the mock instead of the server.
    @Test
    func engineServesTheMock() async throws {
        let directory = try TemporaryDirectory(prefix: "watcher-mocks")
        try await withHarness { harness in
            let captured = Flow.fixture(
                request: .fixture(
                    scheme: "http",
                    host: "upstream.test",
                    port: harness.upstream.port,
                    path: "/mocked?x=1"
                ),
                response: .fixture(
                    headers: [Header("Content-Type", "application/json"), Header("Content-Length", "7")],
                    body: Data(#"{"from":"mock"}"#.utf8)
                ),
                state: .pending
            )
            let mock = try MockMaker.make(from: captured, in: directory.appending("mocks"))
            try await harness.reconfigure { $0.mapLocal = RuleSet(isEnabled: true, rules: [mock.rule]) }
            let (status, body) = try await harness.get("/mocked?x=2")
            #expect(status == 200); #expect(body == #"{"from":"mock"}"#)
        }
    }
}
