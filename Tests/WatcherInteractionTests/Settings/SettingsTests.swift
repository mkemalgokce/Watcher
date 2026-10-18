import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct SettingsTests {
        @Test
        func settingsShowsAndControlsTheProxy() async throws {
            let model = try AppModel.test()
            model.settings.port = 70000
            try await withWindow(showing: SettingsView().environment(model), width: 560, height: 520) { window in
                #expect(!window.elements("Stopped").isEmpty)
                try await window.press("Start")
                #expect(!model.proxy.isRunning, "an invalid port is refused")
                #expect(model.proxy.proxyError?.contains("not valid") == true)
                await settle()
                #expect(!window.elements("Failed to start").isEmpty, "the status row says it failed")
            }
        }
    }
}
