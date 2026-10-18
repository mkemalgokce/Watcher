import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The bottom status bar and the notice banner, built from view models with test doubles.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRunOnThisOS, "no references for this macOS and recording is off")
)
struct MainWindowSnapshotTests {
    private static let size = CGSize(width: 900, height: 28)

    private func model(_ flows: [Flow] = []) throws -> AppModel {
        let model = try AppModel.test()
        model.engine.store.load(flows)
        model.list.syncFromStore()
        return model
    }

    @Test
    func statusBarWhileStopped() throws {
        let model = try model([.fixture(sequence: 1, status: 200, body: Data(count: 2048))])
        ImageSnapshot.verify(StatusBar().environment(model), size: Self.size, named: "stopped")
    }

    @Test
    func statusBarWithToolsAndPausedTraffic() async throws {
        let model = try model([.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 500)])
        model.settings.noCaching = true
        model.settings.blockList = RuleSet(isEnabled: true, rules: [BlockRule(matching: MatchingRule(pattern: "*"))])
        model.breakpoints.hits = [.init(phase: .request, request: .fixture(), pausedAt: .distantPast)]
        model.proxy.toggleRunning()
        #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
        ImageSnapshot.verify(StatusBar().environment(model), size: Self.size, named: "busy")
    }

    @Test(arguments: [Notice.Kind.success, .info, .error])
    func noticeBannerForEachKind(kind: Notice.Kind) throws {
        let model = try model()
        model.notices.notify("Saved 12 requests to session.watcher", kind)
        ImageSnapshot.verify(
            NoticeBanner().environment(model).padding(8),
            size: CGSize(width: 460, height: 64),
            named: "\(kind)"
        )
    }
}

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
