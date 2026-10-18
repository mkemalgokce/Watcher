import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@Suite(.tags(.smoke, .integration))
struct SmokeTests {
    @Test(.tags(.network))
    func engineStartsOnAFreePortAndForwardsAGetToTheOrigin() async throws {
        let (port, response) = try await withHarness { harness in
            try await (harness.proxyPort, harness.get("/hello"))
        }
        #expect(port > 0)
        #expect(response.status == 200)
        #expect(response.body.hasPrefix("GET /hello host=upstream.test"))
    }

    @Test
    func sessionSavedToDiskLoadsBackTheSameFlows() throws {
        let directory = try TemporaryDirectory()
        let file = directory.appending("session.watcher")
        let flows = [
            Flow.fixture(sequence: 1),
            .fixture(sequence: 2, request: .fixture(method: "POST", path: "/v1/users"), response: nil),
        ]
        try SessionFile.encode(flows).write(to: file)
        let loaded = try SessionFile.decode(Data(contentsOf: file))
        #expect(loaded.map(\.id) == flows.map(\.id))
        #expect(loaded.map(\.request) == flows.map(\.request))
        #expect(loaded.map(\.response) == flows.map(\.response))
        #expect(loaded.map(\.state) == [.completed, .failed])
    }

    @Test @MainActor
    func appModelBuildsWithoutListening() {
        let model = AppModel(listening: false)
        #expect(model.flows.isEmpty)
        #expect(!model.isRunning)
    }
}
