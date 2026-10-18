import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The bottom status bar, built from its view model with test doubles.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct StatusBarTests {
    private static let size = CGSize(width: 900, height: 28)

    private func model(_ flows: [Flow] = []) throws -> AppModel {
        let model = try AppModel.test()
        model.engine.store.load(flows)
        model.list.syncFromStore()
        return model
    }

    @Test
    func statusBarWhileStopped() async throws {
        let model = try model([.fixture(sequence: 1, status: 200, body: Data(count: 2048))])
        let bar = StatusBar(viewModel: model.statusBar).environment(model)
        await ImageSnapshot.verify(bar, size: Self.size, named: "stopped")
    }

    @Test
    func statusBarWithToolsAndPausedTraffic() async throws {
        let model = try model([.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 500)])
        model.settings.noCaching = true
        model.settings.blockList = RuleSet(isEnabled: true, rules: [BlockRule(matching: MatchingRule(pattern: "*"))])
        model.breakpoints.hits = [.init(phase: .request, request: .fixture(), pausedAt: .distantPast)]
        model.proxy.toggleRunning()
        #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
        let bar = StatusBar(viewModel: model.statusBar).environment(model)
        await ImageSnapshot.verify(bar, size: Self.size, named: "busy")
    }
}
