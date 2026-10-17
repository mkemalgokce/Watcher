import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// Clearing the session hands back what it removed, so the UI can offer Undo, and restoring puts it back in front.
@Suite(.tags(.unit))
struct FlowStoreClearTests {
    @Test
    func clearReturnsTheRemovedFlowsInOrder() {
        let store = FlowStore()
        let flows = ["/a", "/b", "/c"].map { store.begin(.fixture(path: $0)) }
        #expect(store.clear().map(\.id) == flows.map(\.id))
        #expect(store.all.isEmpty)
    }

    @Test
    func clearOnAnEmptyStoreReturnsNothing() {
        #expect(FlowStore().clear().isEmpty)
    }

    @Test
    func restorePutsClearedFlowsBeforeLaterOnesAndRenumbers() {
        let store = FlowStore()
        let first = store.begin(.fixture(path: "/a"))
        store.update(first.id) { $0.comment = "kept" }
        _ = store.begin(.fixture(path: "/b"))
        let removed = store.clear()
        let later = store.begin(.fixture(path: "/later"))

        store.restore(removed)

        #expect(store.all.map(\.request.path) == ["/a", "/b", "/later"])
        #expect(store.all.map(\.sequence) == [1, 2, 3], "numbers stay unique and in list order")
        #expect(store.all.first?.comment == "kept", "edits made before clearing come back")
        #expect(store.all.last?.id == later.id)
        let next = store.begin(.fixture(path: "/next"))
        #expect(next.sequence == 4, "the next request continues after the restored ones")
    }

    @Test
    func restoreSkipsFlowsThatAreAlreadyStored() {
        let store = FlowStore()
        let flow = store.begin(.fixture(path: "/a"))
        store.restore([flow])
        #expect(store.all.map(\.id) == [flow.id])
    }

    @Test
    func restoreKeepsTheNewestWithinTheLimit() {
        let store = FlowStore()
        store.maxFlows = 2
        _ = ["/a", "/b"].map { store.begin(.fixture(path: $0)) }
        let removed = store.clear()
        _ = store.begin(.fixture(path: "/later"))
        store.restore(removed)
        #expect(store.all.map(\.request.path) == ["/b", "/later"])
    }

    @Test
    func restoreTellsObserversToRebuildTheList() async {
        let store = FlowStore()
        _ = store.begin(.fixture(path: "/a"))
        let removed = store.clear()
        let events = store.events()
        store.restore(removed)
        var seen: [String] = []
        for await event in events {
            switch event {
            case .cleared: seen.append("cleared")
            case let .added(flow): seen.append(flow.request.path)
            default: seen.append("other")
            }
            if seen.count == 2 {
                break
            }
        }
        #expect(seen == ["cleared", "/a"])
    }
}
