import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The general settings form, built from its view models with test doubles.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct SettingsViewTests {
    @Test
    func theGeneralSettings() async throws {
        let model = try AppModel.test()
        model.settings.port = 80
        await ImageSnapshot.verify(
            SettingsView().environment(model), size: CGSize(width: 520, height: 470), named: "general"
        )
    }
}
