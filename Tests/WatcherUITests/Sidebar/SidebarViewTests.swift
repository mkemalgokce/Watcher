import AppKit
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The sidebar on screen, with traffic arriving.
@MainActor
@Suite(.serialized, .tags(.ui))
struct SidebarViewTests {
    /// Traffic arriving while the sidebar is on screen leaves the selection on All Requests. (Once seen jumping to
    /// Starred in the running app; that could not be reproduced here, so this checks the behaviour, not that cause.)
    @Test
    func sidebarKeepsItsSelectionWhenTrafficArrives() async throws {
        let model = AppModel(listening: false)
        let window = NSWindow.hosting(SidebarView().environment(model), size: CGSize(width: 260, height: 600))
        defer { window.close() }
        window.orderFront(nil) // the outline view only shifts its selection while it is really on screen
        let outline = try #require(window.contentView?.firstDescendant(of: NSTableView.self))
        #expect(await eventually { window.isVisible && outline.numberOfRows > 0 }, "the sidebar never drew its rows")
        let rowsBeforeTraffic = outline.numberOfRows
        model.observeEngine()
        model.loadDemoData() // through store events, as live traffic arrives
        #expect(
            await eventually { model.visibleFlows.count == 5 && outline.numberOfRows > rowsBeforeTraffic },
            "the Apps and Domains sections never appeared"
        )
        #expect(model.sidebar == .all)
        #expect(model.visibleFlows.count == 5)
    }
}
