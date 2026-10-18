import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension AppModelTests {
    /// Clear removes every request at once, so the notice offers Undo for a few seconds.
    @MainActor
    struct Clear {
        @Test
        func clearOffersUndoThatBringsTheRequestsBack() {
            let model = AppModel(listening: false)
            let store = model.engine.store
            let kept = ["/a", "/b"].map { store.begin(.fixture(host: "x.test", path: $0)) }
            model.clear()
            #expect(store.all.isEmpty)
            #expect(model.notice?.message == "Cleared 2 requests")
            let undo = model.notice?.action
            #expect(undo?.title == "Undo")

            undo?.perform()
            #expect(store.all.map(\.id) == kept.map(\.id))
            #expect(model.notice?.action == nil, "the follow-up notice cannot undo again")
            undo?.perform()
            #expect(store.all.count == 2, "a second tap on a stale Undo adds nothing")
        }

        @Test
        func clearingAnEmptySessionOffersNoUndo() {
            let model = AppModel(listening: false)
            model.clear()
            #expect(model.notice?.action == nil)
        }
    }
}
