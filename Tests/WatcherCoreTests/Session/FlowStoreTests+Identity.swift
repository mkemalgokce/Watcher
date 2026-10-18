import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension FlowStoreTests {
    struct Identity {
        private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
        private let start = Date(timeIntervalSinceReferenceDate: 42)

        @Test
        func aBegunFlowTakesItsIDAndStartTimeFromTheStore() {
            let store = FlowStore(now: { start }, makeID: { id })
            let flow = store.begin(.fixture())
            #expect(flow.id == id)
            #expect(flow.startedAt == start)
            #expect(store.all.map(\.id) == [id])
        }
    }
}
