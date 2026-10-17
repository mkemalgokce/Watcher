import AppKit
import Observation
@testable import WatcherUI
import XCTest

/// A sidebar with hundreds of domains must not redraw every row each time one site's icon arrives.
@MainActor
final class IconStoreTests: XCTestCase {
    func testAFaviconArrivingRedrawsOnlyItsOwnRow() {
        let store = IconStore()
        let otherRowChanged = Flag()
        withObservationTracking {
            _ = store.favicon(for: "a.example", fetch: false)
        } onChange: {
            otherRowChanged.set()
        }
        store.setFavicon(NSImage(size: NSSize(width: 16, height: 16)), for: "b.example")
        XCTAssertFalse(otherRowChanged.value, "b.example's icon must not invalidate a.example's row")

        let ownRowChanged = Flag()
        withObservationTracking {
            _ = store.favicon(for: "c.example", fetch: false)
        } onChange: {
            ownRowChanged.set()
        }
        store.setFavicon(NSImage(size: NSSize(width: 16, height: 16)), for: "c.example")
        XCTAssertTrue(ownRowChanged.value, "the row whose icon arrived redraws")
        XCTAssertNotNil(store.favicon(for: "c.example", fetch: false))
    }
}

/// Set from Observation's onChange, which may run on another thread.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false
    var value: Bool {
        lock.withLock { isSet }
    }

    func set() {
        lock.withLock { isSet = true }
    }
}
