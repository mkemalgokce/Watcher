import SwiftUI
@testable import WatcherCore
@testable import WatcherUI
import XCTest

extension InteractionTests {
    func testToolbarClearEmptiesTheListAndUndoBringsItBack() {
        let model = AppModel.preview()
        model.onboardingDone = true
        show(ContentView().environment(model), width: 1320, height: 780)
        let before = model.engine.store.all.map(\.id)
        XCTAssertFalse(before.isEmpty)

        press("Clear")
        waitUntil { model.flows.isEmpty }
        XCTAssertTrue(model.engine.store.all.isEmpty)
        press("Undo")
        waitUntil { model.flows.count == before.count }
        XCTAssertEqual(model.engine.store.all.map(\.id), before)
    }
}
