import Foundation
@testable import WatcherCore
import XCTest

/// Clearing the session hands back what it removed, so the UI can offer Undo, and restoring puts it back in front.
final class FlowStoreClearTests: XCTestCase {
    private func request(_ path: String) -> RequestRecord {
        RequestRecord(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: path)
    }

    func testClearReturnsTheRemovedFlowsInOrder() {
        let store = FlowStore()
        let flows = ["/a", "/b", "/c"].map { store.begin(request($0)) }
        XCTAssertEqual(store.clear().map(\.id), flows.map(\.id))
        XCTAssertTrue(store.all.isEmpty)
    }

    func testClearOnAnEmptyStoreReturnsNothing() {
        XCTAssertTrue(FlowStore().clear().isEmpty)
    }

    func testRestorePutsClearedFlowsBeforeLaterOnesAndRenumbers() {
        let store = FlowStore()
        var first = store.begin(request("/a"))
        store.update(first.id) { $0.comment = "kept" }
        first = store.all[0]
        _ = store.begin(request("/b"))
        let removed = store.clear()
        let later = store.begin(request("/later"))

        store.restore(removed)

        XCTAssertEqual(store.all.map(\.request.path), ["/a", "/b", "/later"])
        XCTAssertEqual(store.all.map(\.sequence), [1, 2, 3], "numbers stay unique and in list order")
        XCTAssertEqual(store.all.first?.comment, "kept", "edits made before clearing come back")
        XCTAssertEqual(store.all.last?.id, later.id)
        XCTAssertEqual(store.begin(request("/next")).sequence, 4, "the next request continues after the restored ones")
    }

    func testRestoreSkipsFlowsThatAreAlreadyStored() {
        let store = FlowStore()
        let flow = store.begin(request("/a"))
        store.restore([flow])
        XCTAssertEqual(store.all.map(\.id), [flow.id])
    }

    func testRestoreKeepsTheNewestWithinTheLimit() {
        let store = FlowStore()
        store.maxFlows = 2
        _ = ["/a", "/b"].map { store.begin(request($0)) }
        let removed = store.clear()
        _ = store.begin(request("/later"))
        store.restore(removed)
        XCTAssertEqual(store.all.map(\.request.path), ["/b", "/later"])
    }

    func testRestoreTellsObserversToRebuildTheList() async {
        let store = FlowStore()
        _ = store.begin(request("/a"))
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
        XCTAssertEqual(seen, ["cleared", "/a"])
    }
}
