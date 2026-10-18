import Testing
import WatcherCore
@testable import WatcherUI

@Suite(.tags(.unit))
struct BreakpointRulePhasesTests {
    @Test(arguments: [
        (true, true, "request + response"), (true, false, "request"), (false, true, "response"), (false, false, ""),
    ])
    func theRuleNamesWhatItStops(onRequest: Bool, onResponse: Bool, summary: String) {
        let rule = BreakpointRule(matching: MatchingRule(pattern: "*"), onRequest: onRequest, onResponse: onResponse)
        #expect(rule.phaseSummary == summary)
    }
}
