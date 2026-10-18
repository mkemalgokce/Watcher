import Foundation
import SnapshotTesting
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// The bottom bar: what it says and shows while stopped, recording and with traffic-changing tools on.
    @MainActor
    struct MainWindow {
        private func describe(_ bar: StatusBarViewModel) -> String {
            [
                "state: \(bar.stateTone)",
                "line: \(bar.line)",
                "lan: \(bar.lanAddress ?? "none")",
                "system proxy: \(bar.systemProxyText) [\(bar.systemProxyTone)]",
                "https: \(bar.https.text)",
                "tools: \(bar.activeTools.isEmpty ? "none" : bar.toolsText)",
                "paused: \(bar.pausedCount)",
                "summary: \(bar.summary)",
            ].joined(separator: "\n")
        }

        @Test
        func theStatusBarWhileStoppedAndWhileRecordingWithToolsOn() async throws {
            let probe = DevicesViewModel.DeviceProbe(
                simulators: { [] }, androidDevices: { [] }, isMacTrusted: { false }, lanAddresses: { ["192.168.1.5"] }
            )
            let model = try AppModel(dependencies: .test(devices: probe))
            model.engine.store.load([.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 500)])
            model.list.syncFromStore()
            var texts = [describe(model.statusBar)]

            model.settings.listenOnAllInterfaces = true
            model.settings.noCaching = true
            model.settings.blockList = RuleSet(isEnabled: true, rules: [NewRule.block()])
            model.breakpoints.hits = [.init(phase: .request, request: .fixture(), pausedAt: .distantPast)]
            model.proxy.toggleRunning()
            #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
            texts.append(describe(model.statusBar))
            assertSnapshot(of: texts.joined(separator: "\n\n"), as: .lines)
        }
    }
}
