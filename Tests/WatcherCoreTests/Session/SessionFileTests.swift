import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SessionFileTests {
    @Test
    func sessionRoundTripLoadsIntoTheStore() throws {
        let flows = try SessionFile.decode(SessionFile.encode([Flow.jsonPostFixture()]))
        let store = FlowStore()
        store.load(flows)
        #expect(store.all.count == 1)
        #expect(store.all[0].sequence == 1)
    }

    @Test
    func starAndCommentPersistAndOldSessionsStillLoad() throws {
        var flow = Flow.fixture(
            request: .fixture(path: "/a"),
            response: .fixture(headers: [Header("Content-Type", "application/json")])
        )
        flow.isStarred = true; flow.comment = "check"
        let back = try SessionFile.decode(SessionFile.encode([flow])).first
        #expect(back?.isStarred == true); #expect(back?.comment == "check")
        let request: [String: Any] = [
            "method": "GET", "scheme": "http", "host": "h", "port": 80, "path": "/", "headers": [], "body": "",
        ]
        let legacy = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString,
            "sequence": 1,
            "startedAt": 0,
            "request": request,
            "state": "pending",
            "appliedTools": [],
        ] as [String: Any])
        #expect(throws: Never.self) { try JSONDecoder().decode(Flow.self, from: legacy) }
    }
}
