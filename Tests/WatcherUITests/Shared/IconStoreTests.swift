import AppKit
import Observation
import Testing
import WatcherTestSupport
@testable import WatcherUI

/// A sidebar with hundreds of domains must not redraw every row each time one site's icon arrives.
@MainActor
@Suite(.tags(.unit))
struct IconStoreTests {
    @Test
    func aFaviconArrivingRedrawsOnlyItsOwnRow() {
        let store = IconStore()
        let otherRowChanged = ObservationFlag()
        withObservationTracking {
            _ = store.favicon(for: "a.example", fetch: false)
        } onChange: {
            otherRowChanged.set()
        }
        store.setFavicon(NSImage(size: NSSize(width: 16, height: 16)), for: "b.example")
        #expect(!otherRowChanged.value, "b.example's icon must not invalidate a.example's row")

        let ownRowChanged = ObservationFlag()
        withObservationTracking {
            _ = store.favicon(for: "c.example", fetch: false)
        } onChange: {
            ownRowChanged.set()
        }
        store.setFavicon(NSImage(size: NSSize(width: 16, height: 16)), for: "c.example")
        #expect(ownRowChanged.value, "the row whose icon arrived redraws")
        #expect(store.favicon(for: "c.example", fetch: false) != nil)
    }
}
