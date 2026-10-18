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

    @Test(arguments: [
        (true, "Login", "on  Login · request + response"),
        (false, "", "off * · request + response"),
    ])
    func theSummaryLineSaysIfItIsOnItsTitleAndWhatItStops(isEnabled: Bool, name: String, line: String) {
        let rule = BreakpointRule(name: name, isEnabled: isEnabled, matching: MatchingRule(pattern: "*"))
        #expect(rule.summaryLine == line)
    }
}
