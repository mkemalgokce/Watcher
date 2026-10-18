import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@Suite(.tags(.unit))
struct BreakpointRuleDisplayNameTests {
    @Test(arguments: [("login", "login"), ("", "api.example.com/*")])
    func theNameOrElseThePattern(name: String, expected: String) {
        let rule = BreakpointRule(name: name, matching: MatchingRule(pattern: "api.example.com/*"))
        #expect(rule.displayName == expected)
    }
}
