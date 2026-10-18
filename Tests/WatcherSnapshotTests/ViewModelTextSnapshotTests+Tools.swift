import SnapshotTesting
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// The Tools sidebar with every tool in use, and what the status bar and toolbar badge make of it.
    @MainActor
    struct Tools {
        @Test
        func everyToolInUse() throws {
            let model = try AppModel.test()
            model.settings.value = .everythingChanged
            model.settings.reverseProxy = RuleSet(isEnabled: true, rules: [
                ReverseProxyRule(localPort: 9191, remoteHost: "example.com"),
                ReverseProxyRule(localPort: 9191, remoteHost: "example.com"),
            ])
            let tools = model.toolsViewModel()
            var lines = ToolPage.groups.flatMap { title, group in
                ["[\(title)]"] + group.map { "\($0.rawValue): \(tools.summary($0))" }
            }
            lines.append("status bar: " + ToolPage.activeNames(in: model.settings.value).joined(separator: ", "))
            lines.append("toolbar badge: \(ToolPage.activeRuleCount(in: model.settings.value))")
            assertSnapshot(of: lines.joined(separator: "\n"), as: .lines)
        }
    }
}
