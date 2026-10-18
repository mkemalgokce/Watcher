import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension FlowTests {
    struct Identity {
        private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        private let start = Date(timeIntervalSinceReferenceDate: 10)

        @Test
        func aFlowCanBeGivenItsIDAndStartTime() {
            let flow = Flow(sequence: 1, request: .fixture(), id: id, startedAt: start)
            #expect(flow.id == id)
            #expect(flow.startedAt == start)
        }

        @Test
        func aFlowWithFixedIdentityEncodesTheSameEveryTime() throws {
            let request = RequestRecord.fixture(scheme: "http", host: "h", port: 80)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let flow = Flow(sequence: 2, request: request, id: id, startedAt: start)
            let json = try String(bytes: encoder.encode(flow), encoding: .utf8)
            #expect(json == #"{"appliedTools":[],"id":"00000000-0000-0000-0000-000000000001","isStarred":false,"#
                + #""request":{"body":"","headers":[],"host":"h","method":"GET","path":"\/","port":80,"#
                + #""scheme":"http"},"sequence":2,"startedAt":10,"state":"pending","webSocketMessages":[]}"#)
        }
    }
}
