import SnapshotTesting
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// The Breakpoints window: its rules.
    @MainActor
    struct Breakpoints {
        @Test
        func ruleSummaries() throws {
            let model = try AppModel.test()
            model.settings.breakpoints = RuleSet(isEnabled: true, rules: [
                BreakpointRule(name: "Login", matching: MatchingRule(pattern: "*/login")),
                BreakpointRule(matching: MatchingRule(pattern: "api.example.com/*"), onResponse: false),
                BreakpointRule(isEnabled: false, matching: MatchingRule(pattern: "*")),
            ])
            let lines = model.settings.breakpoints.rules.map(\.summaryLine)
            assertSnapshot(of: lines.joined(separator: "\n"), as: .lines)
        }
    }
}
