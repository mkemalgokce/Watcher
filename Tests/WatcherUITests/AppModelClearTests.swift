@testable import WatcherCore
@testable import WatcherUI
import XCTest

/// Clear removes every request at once, so the notice offers Undo for a few seconds.
@MainActor
final class AppModelClearTests: XCTestCase {
    func testClearOffersUndoThatBringsTheRequestsBack() {
        let model = AppModel(listening: false)
        let store = model.engine.store
        let kept = ["/a", "/b"].map {
            store.begin(RequestRecord(method: "GET", scheme: "https", host: "x.test", port: 443, path: $0))
        }
        model.clear()
        XCTAssertTrue(store.all.isEmpty)
        XCTAssertEqual(model.notice?.message, "Cleared 2 requests")
        let undo = model.notice?.action
        XCTAssertEqual(undo?.title, "Undo")

        undo?.perform()
        XCTAssertEqual(store.all.map(\.id), kept.map(\.id))
        XCTAssertNil(model.notice?.action, "the follow-up notice cannot undo again")
        undo?.perform()
        XCTAssertEqual(store.all.count, 2, "a second tap on a stale Undo adds nothing")
    }

    func testClearingAnEmptySessionOffersNoUndo() {
        let model = AppModel(listening: false)
        model.clear()
        XCTAssertNil(model.notice?.action)
    }
}
