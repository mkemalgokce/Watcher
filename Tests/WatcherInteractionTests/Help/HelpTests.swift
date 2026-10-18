import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct HelpTests {
        @Test
        func helpSearchNarrowsTheShortcuts() async {
            await withWindow(showing: HelpView(), width: 640, height: 560) { window in
                // Each row is read as "title: spoken shortcut", e.g. "Repeat: Command R".
                let repeatRow = "Repeat: \(Shortcut.spoken("⌘R"))"
                let proxyRow = "Record or pause (starts and stops the proxy): \(Shortcut.spoken("⌘E"))"
                #expect(await eventually { !window.elements(repeatRow).isEmpty })
                #expect(await window.type("proxy", role: "AXTextField"), "the search field accepts text")
                #expect(await eventually { !window.elements(proxyRow).isEmpty })
                #expect(await eventually { window.elements(repeatRow).isEmpty }, "unrelated shortcuts are hidden")
            }
        }
    }
}
