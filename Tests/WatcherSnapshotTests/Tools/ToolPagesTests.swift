import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The Tools pages that are forms rather than rule lists.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct ToolPagesTests {
    @Test
    func theThrottlingPage() throws {
        let model = try AppModel.test()
        let throttle = ThrottleSettings(isEnabled: true, profile: NetworkProfile.presets[1], host: "api.example.com")
        let page = ThrottleTab(throttle: .constant(throttle), tool: .throttling).environment(model)
        ImageSnapshot.verify(page, size: CGSize(width: 640, height: 420), named: "throttling")
    }
}
