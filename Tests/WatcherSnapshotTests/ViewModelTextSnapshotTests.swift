import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// What the view models hand the views, as text, which reads the same on every macOS.
@MainActor
@Suite(.tags(.snapshot))
struct ViewModelTextSnapshotTests {
    @Test
    func statusLineInEveryProxyState() async throws {
        let runner = ProxyRunnerStub()
        let model = try AppModel(dependencies: .test(runner: runner))
        model.engine.store.load([.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 404)])
        model.list.syncFromStore()
        var lines = [model.statusLine]
        model.proxy.toggleRunning()
        lines.append(model.statusLine)
        _ = await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy }
        model.list.query.statusClasses = [4]
        lines.append(model.statusLine)
        model.proxy.toggleRunning()
        lines.append(model.statusLine)
        _ = await eventually { !model.proxy.isSwitchingProxy }
        runner.failStarting()
        model.proxy.toggleRunning()
        _ = await eventually { model.proxy.proxyError != nil }
        lines.append(model.statusLine)
        assertSnapshot(of: lines.joined(separator: "\n"), as: .lines)
    }

    @Test
    func sectionsOfEachSideOfAWebSocketExchange() {
        let flow = Flow.fixture(sequence: 1, request: .fixture(path: "/socket?room=1"), response: .fixture(status: 101))
        let text = MessageSide.allCases.map { side in
            let panel = MessagePanelViewModel(flow: flow, side: side, previewersActive: true, embedded: [])
            let sections = panel.available.map { "\($0.rawValue)\(panel.count($0).map { " (\($0))" } ?? "")" }
            return "\(side.rawValue): \(sections.joined(separator: ", ")) · \(panel.detail)"
        }
        assertSnapshot(of: text.joined(separator: "\n"), as: .lines)
    }
}
