import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Opening Compare from the window, and comparing an Edit & Repeat with the request it came from.
@MainActor
struct AppModelCompareTests {
    @Test
    func compareOpensTheWindowWithABase() {
        let model = AppModel(listening: false)
        let base = Flow.fixture(sequence: 1, status: 200)
        model.compare(withBase: base)
        #expect(model.diffBase?.id == base.id)
        #expect(model.compareWindowRequest == 1)
    }

    @Test
    func compareWithOriginalSelectsTheResentRequest() {
        let model = AppModel(listening: false)
        let captured = RequestRecord.fixture(method: "POST", path: "/v1/items?x=1", body: Data(#"{"name":"A"}"#.utf8))
        let original = Flow.fixture(sequence: 1, request: captured, response: nil, state: .completed)
        let other = Flow.fixture(sequence: 2, request: .fixture(path: "/other"), response: nil, state: .completed)
        let resent = Flow.fixture(sequence: 3, request: captured, response: nil, state: .completed)
        [original, other, resent].forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        model.editAndRepeat(original)
        #expect(model.sheet == .compose)
        #expect(model.composeSource?.id == original.id)

        model.compareWithOriginal(original, sent: captured)
        #expect(model.diffBase?.id == original.id)
        #expect(model.selection == resent.id)
        #expect(model.sheet == nil)
    }
}
