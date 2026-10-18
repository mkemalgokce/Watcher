import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct AllowListToolTests {
    private let tool = AllowListTool(rules: [
        AllowRule(matching: MatchingRule(pattern: "*/api/*")),
        AllowRule(matching: MatchingRule(pattern: "*/status")),
    ])

    @Test(arguments: ["/api/users", "/status"])
    func aRequestMatchingAnyRuleIsForwarded(path: String) async {
        var request = RequestRecord.fixture(path: path)
        guard case .forward = await tool.intercept(request: &request) else { Issue.record("expected forward"); return }
    }

    @Test
    func anyOtherRequestIsBlockedAndStaysInTheList() async {
        var request = RequestRecord.fixture(path: "/admin")
        guard case let .block(hidden) = await tool.intercept(request: &request) else {
            Issue.record("expected a block"); return
        }
        #expect(!hidden)
    }

    @Test(arguments: [(nil as String?, false), ("Op", true)])
    func onlyAGraphQLRuleNeedsTheBody(operation: String?, needs: Bool) {
        let rule = AllowRule(matching: MatchingRule(graphQLQueryName: operation))
        #expect(AllowListTool(rules: [rule]).needsRequestBody == needs)
    }
}
