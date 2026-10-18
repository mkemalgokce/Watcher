import Foundation
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The window toolbar and its filter field. An off-screen window has no toolbar, so the content of each is hosted directly.
/// The field draws its tokens there but not the text typed beside them, so that is left to the view model tests.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct ToolbarScreenTests {
    private static let size = CGSize(width: 760, height: 56)
    private static let fieldSize = CGSize(width: 760, height: 100)

    private func toolbar(_ model: AppModel) -> some View {
        HStack(spacing: 16) {
            CaptureControls()
            Spacer()
            ToolControls()
            MoreMenu()
        }
        .padding(.horizontal, 12).environment(model)
    }

    private func filter(_ model: AppModel) -> some View {
        // Only a sidebar draws the field in an off-screen window.
        NavigationSplitView {
            List {}.modifier(FilterSearch(placement: .sidebar)).navigationSplitViewColumnWidth(min: 560, ideal: 560)
        } detail: {
            Color.clear
        }
        .environment(model)
    }

    @Test
    func theToolbarBeforeAnyTraffic() async throws {
        try await ImageSnapshot.verify(toolbar(Screen.model()), size: Self.size, named: "idle")
    }

    @Test
    func theToolbarWhileRecordingWithPausedTraffic() async throws {
        let model = try Screen.demo()
        model.breakpoints.hits = [.init(phase: .request, request: .fixture(), pausedAt: .distantPast)]
        model.proxy.toggleRunning()
        #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
        await ImageSnapshot.verify(toolbar(model), size: Self.size, named: "recording")
    }

    @Test
    func theFilterFieldWithoutAFilter() async throws {
        try await ImageSnapshot.verify(filter(Screen.demo()), size: Self.fieldSize, named: "empty")
    }

    @Test
    func theFilterFieldWithTokens() async throws {
        let model = try Screen.demo()
        model.list.query.methods = ["POST"]
        model.list.query.statusClasses = [4]
        await ImageSnapshot.verify(filter(model), size: Self.fieldSize, named: "filtered")
    }
}
