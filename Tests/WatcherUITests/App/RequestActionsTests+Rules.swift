import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension RequestActionsTests {
    /// Rules made from a captured request or a domain in the sidebar: what they match and that their tool is on.
    @MainActor
    struct Rules {
        @Test(arguments: [
            ("/v1/users?page=2", "api.example.com/v1/users"),
            ("/v1/users", "api.example.com/v1/users"),
            ("/", "api.example.com/"),
            ("", "api.example.com/"),
            ("?page=2", "api.example.com/"),
            ("/?page=2", "api.example.com/"),
        ])
        func aBreakpointMatchesTheRequestsHostAndPathWithoutItsQuery(path: String, pattern: String) {
            #expect(RequestActions.breakpointPattern(for: .fixture(host: "api.example.com", path: path)) == pattern)
        }

        @Test
        func addingABreakpointSwitchesBreakpointsOnAndNamesTheRuleAfterTheHost() throws {
            let model = try AppModel.test()
            model.actions.addBreakpoint(for: .fixture(host: "api.example.com", path: "/v1/login?next=/"))
            #expect(model.settings.breakpoints.isEnabled)
            #expect(model.settings.breakpoints.rules == [
                BreakpointRule(name: "api.example.com", matching: MatchingRule(pattern: "api.example.com/v1/login")),
            ])
        }

        @Test
        func blockingAHostMatchesOnlyThatHost() throws {
            let model = try AppModel.test()
            model.actions.blockHost("ads.example.com")
            #expect(model.settings.blockList.isEnabled)
            #expect(model.settings.blockList.rules == [
                BlockRule(name: "ads.example.com", matching: MatchingRule(pattern: "ads.example.com/*")),
            ])
        }

        @Test
        func blockingADomainAlsoMatchesItsSubdomainsAndSaysWhereToUndoIt() throws {
            let model = try AppModel.test()
            model.actions.blockDomain("tracker.net")
            #expect(model.settings.blockList.isEnabled)
            #expect(model.settings.blockList.rules == [
                BlockRule(name: "tracker.net", matching: MatchingRule(pattern: "*tracker.net/*")),
            ])
            #expect(model.notices.notice?.message == "Requests to tracker.net are now blocked (Tools ▸ Block List)")
            #expect(model.notices.notice?.kind == .success)
        }

        @Test
        func blockingKeepsTheRulesAlreadyThere() throws {
            let model = try AppModel.test()
            model.actions.blockHost("a.example")
            model.actions.blockDomain("b.example")
            #expect(model.settings.blockList.rules.map(\.matching.pattern) == ["a.example/*", "*b.example/*"])
        }
    }
}
