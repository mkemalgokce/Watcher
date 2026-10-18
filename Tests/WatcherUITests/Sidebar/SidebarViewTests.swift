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
        let model = try AppModel.test(sleep: liveSleep) // the list batches store events on a delay
        let window = NSWindow.hosting(SidebarView().environment(model), size: CGSize(width: 260, height: 600))
        defer { window.close() }
        window.orderFront(nil) // the outline view only shifts its selection while it is really on screen
        let outline = try #require(window.contentView?.firstDescendant(of: NSTableView.self))
        let drawn = await eventually(timeout: 15) { window.isVisible && outline.numberOfRows > 0 }
        #expect(drawn, "the sidebar never drew its rows")
        let rowsBeforeTraffic = outline.numberOfRows
        model.observeEngine()
        model.loadDemoData() // through store events, as live traffic arrives
        let sectionsAppeared = await eventually(timeout: 15) {
            model.list.visibleFlows.count == 5 && outline.numberOfRows > rowsBeforeTraffic
        }
        #expect(sectionsAppeared, "the Apps and Domains sections never appeared")
        #expect(model.list.sidebar == .all)
        #expect(model.list.visibleFlows.count == 5)
    }
}
