import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension FlowListViewModelTests {
    /// Events applied together: the edge cases of several events about one flow in a single batch.
    @MainActor
    struct Batches {
        private let store = FlowStore()

        private func list() -> FlowListViewModel {
            FlowListViewModel(store: store, sleep: sleepUntilCancelled)
        }

        @Test
        func aFlowRemovedAndAddedAgainInOneBatchStaysInItsPlace() {
            let list = list()
            let flows = (1 ... 3).map { Flow.fixture(sequence: $0, status: 200) }
            flows.forEach { list.enqueue(.added($0)) }
            list.flushEvents()
            list.enqueue(.removed(flows[1].id))
            list.enqueue(.added(flows[1]))
            list.flushEvents()
            #expect(list.flows.map(\.sequence) == [1, 2, 3])
        }

        @Test
        func anUpdateAfterARemovalInOneBatchDoesNotBringTheFlowBack() {
            let list = list()
            let flow = Flow.fixture(sequence: 1, status: 200)
            list.enqueue(.added(flow))
            list.flushEvents()
            list.enqueue(.removed(flow.id))
            list.enqueue(.updated(flow))
            list.flushEvents()
            #expect(list.flows.isEmpty)
        }

        @Test
        func flowsAddedAfterAClearInOneBatchAreKept() {
            let list = list()
            list.enqueue(.added(.fixture(sequence: 1, status: 200)))
            list.flushEvents()
            list.enqueue(.cleared)
            list.enqueue(.added(.fixture(sequence: 2, status: 200)))
            list.flushEvents()
            #expect(list.flows.map(\.sequence) == [2])
        }

        @Test
        func theSelectionSurvivesAnUpdateOfTheSelectedFlow() {
            let list = list()
            let flow = Flow.fixture(sequence: 1, status: 200)
            list.enqueue(.added(flow))
            list.flushEvents()
            list.selection = flow.id
            var changed = flow; changed.comment = "x"
            list.enqueue(.updated(changed))
            list.flushEvents()
            #expect(list.selection == flow.id)
            #expect(list.selectedFlow?.comment == "x")
        }
    }
}
