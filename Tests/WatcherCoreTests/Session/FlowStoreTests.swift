import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// The session's requests: clearing hands back what it removed so the UI can offer Undo, restoring puts it back in
/// front, and observers, which rebuild the list from events, get them in the order the store applied the changes.
@Suite(.tags(.unit))
struct FlowStoreTests {
    private let iterations = 500

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

    @Test
    func concurrentBeginsAreObservedInSequenceOrder() async {
        let store = FlowStore()
        let events = store.events()

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = store.begin(.fixture(scheme: "http", host: "example.test", port: 80))
        }

        var added: [Flow] = []
        for await event in events {
            if case let .added(flow) = event {
                added.append(flow)
            }
            if added.count == iterations {
                break
            }
        }
        #expect(added.map(\.sequence) == Array(1 ... iterations))
        #expect(added.map(\.startedAt) == added.map(\.startedAt).sorted())
    }

    @Test
    func concurrentWebSocketMessagesAreObservedInOrder() async {
        let store = FlowStore()
        let flow = store.begin(.fixture(scheme: "ws", host: "example.test", port: 80))
        let events = store.events()

        let message = WebSocketMessage(direction: .serverToClient, kind: .text, payload: Data("x".utf8))
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            store.appendWebSocketMessage(message, to: flow.id)
        }

        var counts: [Int] = []
        for await event in events {
            if case let .updated(updated) = event {
                counts.append(updated.webSocketMessages.count)
            }
            if counts.count == iterations {
                break
            }
        }
        #expect(counts == Array(1 ... iterations))
    }
}
