import ApplicationServices
import Foundation
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
                #expect(
                    await eventually { !window.elements("Failed to start").isEmpty },
                    "the status row says it failed"
                )
            }
        }

        /// The viewer opens bodies as Preview until another mode is chosen; Settings must show the same choice.
        @Test
        func theViewerTabSelectsTheModeBodiesOpenIn() async throws {
            let unset = try #require(UserDefaults(suiteName: "watcher-tests-\(UUID().uuidString)"))
            let model = try AppModel.test()
            let view = SettingsView().environment(model).defaultAppStorage(unset)
            try await withWindow(showing: view, width: 560, height: 520) { window in
                try await window.press("Viewer")
                let segment = window.elements("Preview").first { Self.role(of: $0) == kAXRadioButtonRole }
                let preview = try #require(segment, "Settings offers no Preview mode")
                #expect(Self.value(of: preview) == 1, "Preview is the selected mode")
            }
        }

        private static func role(of element: AXUIElement) -> String? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
            return value as? String
        }

        private static func value(of element: AXUIElement) -> Int? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            return (value as? NSNumber)?.intValue
        }
    }
}
