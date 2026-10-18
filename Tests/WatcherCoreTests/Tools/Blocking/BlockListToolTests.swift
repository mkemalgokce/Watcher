import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct BlockListToolTests {
    private func decide(_ rules: [BlockRule], _ request: RequestRecord) async -> RequestDecision {
        var request = request
        return await BlockListTool(rules: rules).intercept(request: &request)
    }

    @Test(arguments: [true, false])
    func aMatchingRuleBlocksAndSaysWhetherToHideTheRequest(hides: Bool) async {
        let rule = BlockRule(matching: MatchingRule(pattern: "*/ads/*"), hidesRequest: hides)
        guard case let .block(hidden) = await decide([rule], .fixture(path: "/ads/banner")) else {
            Issue.record("expected a block"); return
        }
        #expect(hidden == hides)
    }

    @Test
    func theFirstMatchingRuleDecidesWhetherToHide() async {
        let rules = [
            BlockRule(matching: MatchingRule(pattern: "*/other/*"), hidesRequest: false),
            BlockRule(matching: MatchingRule(pattern: "*/ads/*"), hidesRequest: true),
            BlockRule(matching: MatchingRule(pattern: "*"), hidesRequest: false),
        ]
        guard case let .block(hidden) = await decide(rules, .fixture(path: "/ads/banner")) else {
            Issue.record("expected a block"); return
        }
        #expect(hidden)
    }

    @Test
    func aRequestMatchingNoRuleIsForwarded() async {
        let rule = BlockRule(matching: MatchingRule(pattern: "*/ads/*"))
        guard case .forward = await decide([rule], .fixture(path: "/home")) else {
            Issue.record("expected forward"); return
        }
    }

    @Test(arguments: [(nil as String?, false), ("Op", true)])
    func onlyAGraphQLRuleNeedsTheBody(operation: String?, needs: Bool) {
        let rule = BlockRule(matching: MatchingRule(graphQLQueryName: operation))
        #expect(BlockListTool(rules: [rule]).needsRequestBody == needs)
    }
}
