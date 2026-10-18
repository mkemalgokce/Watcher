import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct ToolsViewTests {
        @Test
        func toolsAddsARuleAndSwitchesTheToolOn() async throws {
            let model = try AppModel.test()
            model.router.toolsSelection = .block
            try await withWindow(showing: ToolsView().environment(model), width: 920, height: 620) { window in
                #expect(model.settings.blockList.rules.isEmpty)
                try await window.press("Add Rule")
                #expect(model.settings.blockList.rules.count == 1)
                #expect(model.settings.blockList.isEnabled, "a new rule works without a second switch")

                model.settings.blockList.isEnabled = false
                #expect(await window.shows("Turn On"))
                try await window.press("Turn On")
                #expect(model.settings.blockList.isEnabled)

                try await window.press("Remove Rule")
                #expect(model.settings.blockList.rules.isEmpty)
            }
        }
    }
}
