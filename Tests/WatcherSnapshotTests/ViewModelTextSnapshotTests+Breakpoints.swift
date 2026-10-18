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
            var lines = model.settings.breakpoints.rules.map { rule in
                "\(rule.isEnabled ? "on " : "off") \(rule.displayName) · \(rule.phaseSummary)"
            }
            let paused = [("api.example.com", "/login"), ("api.example.com", "/v1/users"), ("cdn.a.com", "/a.css")]
            for (host, path) in paused {
                let names = breakpoints.rules(matching: .fixture(host: host, path: path)).map(\.displayName)
                lines.append("\(host)\(path) stops at: \(names.isEmpty ? "nothing" : names.joined(separator: ", "))")
            }
            assertSnapshot(of: lines.joined(separator: "\n"), as: .lines)
        }
    }
}
