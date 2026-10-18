import Foundation
import SnapshotTesting
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// The General settings pane: the status line through a start and a failed start, and the warning for each port.
    @MainActor
    struct Settings {
        @Test
        func theGeneralPaneInEachState() async throws {
            let runner = ProxyRunnerStub(boundPort: 9123)
            let model = try AppModel(dependencies: .test(runner: runner))
            let pane = model.settingsPane
            var lines = ["\(pane.status): \(pane.statusText)"]
            model.proxy.toggleRunning()
            _ = await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy }
            lines.append("\(pane.status): \(pane.statusText)")
            model.proxy.toggleRunning()
            _ = await eventually { !model.proxy.isSwitchingProxy }
            runner.failStarting()
            model.proxy.toggleRunning()
            _ = await eventually { model.proxy.proxyError != nil }
            lines.append("\(pane.status): \(pane.statusText)")
            for port in [0, 80, 1024, 65536] {
                model.settings.port = port
                lines.append("port \(port): \(pane.portWarning?.message ?? "no warning")")
            }
            lines.append("login item: \(pane.opensAtLogin) · website icons: \(pane.showsWebsiteIcons)")
            assertSnapshot(of: lines.joined(separator: "\n"), as: .lines)
        }
    }
}
