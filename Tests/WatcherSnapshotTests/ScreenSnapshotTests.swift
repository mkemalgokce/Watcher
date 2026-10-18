import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Form screens built from view models with test doubles. List rows do not draw off screen, so the request list, the
/// rule lists and Breakpoints are covered by text snapshots of their view models instead.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRunOnThisOS, "no references for this macOS and recording is off")
)
struct ScreenSnapshotTests {
    @Test
    func theGeneralSettings() throws {
        let model = try AppModel.test()
        model.settings.port = 80
        ImageSnapshot.verify(SettingsView().environment(model), size: CGSize(width: 520, height: 470), named: "general")
    }

    @Test
    func theThrottlingPage() throws {
        let model = try AppModel.test()
        let throttle = ThrottleSettings(isEnabled: true, profile: NetworkProfile.presets[1], host: "api.example.com")
        let page = ThrottleTab(throttle: .constant(throttle), tool: .throttling).environment(model)
        ImageSnapshot.verify(page, size: CGSize(width: 640, height: 420), named: "throttling")
    }
}
