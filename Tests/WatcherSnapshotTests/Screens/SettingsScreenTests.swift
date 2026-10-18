import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Every tab of the Settings window, at the size the window has.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct SettingsScreenTests {
    private static let size = CGSize(width: 520, height: 470)

    @Test
    func theGeneralSettings() async throws {
        let model = try Screen.model()
        model.settings.port = 80
        let view = GeneralSettings(pane: model.settingsPane).environment(model)
        await ImageSnapshot.verify(view, size: CGSize(width: 520, height: 720), named: "general")
    }

    @Test
    func theViewerSettings() async throws {
        let model = try Screen.model()
        let view = AppearanceSettings(options: model.viewer).environment(model)
        await ImageSnapshot.verify(view, size: CGSize(width: 520, height: 620), named: "viewer")
    }

    @Test
    func theProxySettings() async throws {
        try await ImageSnapshot.verify(ProxySettings().environment(Screen.model()), size: Self.size, named: "proxy")
    }

    @Test
    func theAdvancedSettings() async throws {
        let model = try Screen.model()
        await ImageSnapshot.verify(AdvancedSettings().environment(model), size: Self.size, named: "advanced")
    }
}
