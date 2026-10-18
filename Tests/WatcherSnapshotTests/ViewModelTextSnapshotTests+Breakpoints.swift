import Foundation
import SnapshotTesting
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// The Breakpoints window: its rules, and which of them stop each paused request.
    @MainActor
    struct Breakpoints {
        @Test
        func rulesAndThePausedRequestsTheyStop() throws {
            let model = try AppModel.test()
            model.settings.breakpoints = RuleSet(isEnabled: true, rules: [
                BreakpointRule(name: "Login", matching: MatchingRule(pattern: "*/login")),
                BreakpointRule(matching: MatchingRule(pattern: "api.example.com/*"), onResponse: false),
                BreakpointRule(isEnabled: false, matching: MatchingRule(pattern: "*")),
            ])
            let breakpoints = model.breakpoints
            var lines = model.settings.breakpoints.rules.map(\.summaryLine)
            let paused = [("api.example.com", "/login"), ("api.example.com", "/v1/users"), ("cdn.a.com", "/a.css")]
            lines += paused.map { breakpoints.stopsAtLine(for: .fixture(host: $0.0, path: $0.1)) }
            assertSnapshot(of: lines.joined(separator: "\n"), as: .lines)
        }
    }
}
