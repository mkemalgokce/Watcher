import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The Tools window on each page, with rules that read like real use.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct ToolScreenTests {
    private static let size = CGSize(width: 920, height: 640)
    private static let tallPages: Set<ToolPage> = [.protobuf, .mapRemote]

    @Test(arguments: ToolPage.allCases)
    func toolsPage(page: ToolPage) async throws {
        let model = try Screen.model()
        model.settings.value = Screen.toolSettings
        model.router.toolsSelection = page
        await ImageSnapshot.verify(
            ToolsView().environment(model),
            size: CGSize(width: Self.size.width, height: Self.tallPages.contains(page) ? 800 : Self.size.height),
            named: page.rawValue
        )
    }

    @Test
    func toolsWithNoRules() async throws {
        let model = try Screen.model()
        await ImageSnapshot.verify(ToolsView().environment(model), size: Self.size, named: "empty")
    }
}
