import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension RequestActionsTests {
    /// Rules made from a captured request or a domain in the sidebar: what they match and that their tool is on.
    @MainActor
    struct Rules {
        private func breakpoint(on path: String) -> MatchingRule {
            RequestActions.breakpointMatching(for: .fixture(host: "api.example.com", path: path))
        }

        private func matches(_ rule: MatchingRule, host: String, path: String) -> Bool {
            rule.compile().matches(.fixture(host: host, path: path))
        }

        @Test(arguments: ["/v1/users?page=2", "/v1/users", "/v1/users?page=3"])
        func aBreakpointMatchesTheRequestItWasMadeFromAndAnyOtherQuery(path: String) {
            let rule = breakpoint(on: "/v1/users?page=2")
            #expect(matches(rule, host: "api.example.com", path: path))
        }

        @Test(arguments: ["/", "", "?page=2"])
        func aRootBreakpointMatchesTheRootWithOrWithoutAQuery(path: String) {
            let rule = breakpoint(on: "/?page=2")
            #expect(matches(rule, host: "api.example.com", path: path))
        }

        @Test(arguments: [
            ("api.example.com", "/v1/users/42"), ("other.example.com", "/v1/users"), ("api.example.com", "/v1"),
        ])
        func aBreakpointDoesNotMatchOtherPathsOrHosts(host: String, path: String) {
            let rule = breakpoint(on: "/v1/users?page=2")
            #expect(!matches(rule, host: host, path: path))
        }

        @Test
        func aBreakpointOnAPathWithRegexCharactersTakesThemLiterally() {
            let rule = RequestActions.breakpointMatching(for: .fixture(host: "a.test", path: "/v1/a+b(c)"))
            #expect(matches(rule, host: "a.test", path: "/v1/a+b(c)"))
            #expect(!matches(rule, host: "a.test", path: "/v1/aab(c)"))
        }

        @Test
        func addingABreakpointSwitchesBreakpointsOnAndNamesTheRuleAfterTheHost() throws {
            let model = try AppModel.test()
            let request = RequestRecord.fixture(host: "api.example.com", path: "/v1/login?next=/")
            model.actions.addBreakpoint(for: request)
            #expect(model.settings.breakpoints.isEnabled)
            #expect(model.settings.breakpoints.rules.map(\.name) == ["api.example.com"])
            #expect(model.settings.breakpoints.rules.first?.matching.compile().matches(request) == true)
        }

        @Test(arguments: [
            ("ads.example.com", "/x", true), ("ads.example.com", "", true), ("cdn.ads.example.com", "/x", false),
            ("example.com", "/x", false), ("a.com", "/?u=ads.example.com/", false),
        ])
        func blockingAHostMatchesOnlyThatHost(host: String, path: String, blocked: Bool) throws {
            let model = try AppModel.test()
            model.actions.blockHost("ads.example.com")
            #expect(model.settings.blockList.isEnabled)
            let rule = try #require(model.settings.blockList.rules.first)
            #expect(rule.name == "ads.example.com")
            #expect(matches(rule.matching, host: host, path: path) == blocked)
        }

        @Test
        func blockingADomainSaysWhereToUndoIt() throws {
            let model = try AppModel.test()
            model.actions.blockDomain("tracker.net")
            #expect(model.settings.blockList.isEnabled)
            #expect(model.settings.blockList.rules.map(\.name) == ["tracker.net"])
            #expect(model.notices.notice?.message == "Requests to tracker.net are now blocked (Tools ▸ Block List)")
            #expect(model.notices.notice?.kind == .success)
        }

        @Test(arguments: [
            ("tracker.net", "/a", true), ("cdn.tracker.net", "/a", true), ("a.b.tracker.net", "/", true),
            ("tracker.net", "", true), ("tracker.net", "?x=1", true),
            ("nottracker.net", "/a", false), ("a.com", "/?u=tracker.net/x", false), ("a.com", "/tracker.net/x", false),
            ("tracker.net.evil.com", "/a", false),
        ])
        func aBlockedDomainMatchesItselfAndItsSubdomainsOnly(host: String, path: String, blocked: Bool) throws {
            let model = try AppModel.test()
            model.actions.blockDomain("tracker.net")
            let rule = try #require(model.settings.blockList.rules.first)
            #expect(matches(rule.matching, host: host, path: path) == blocked)
        }

        @Test
        func blockingTheSameHostTwiceAddsOneRule() throws {
            let model = try AppModel.test()
            model.actions.blockHost("a.example")
            model.actions.blockHost("a.example")
            model.actions.blockDomain("b.example")
            model.actions.blockDomain("b.example")
            #expect(model.settings.blockList.rules.map(\.name) == ["a.example", "b.example"])
        }

        @Test
        func blockingAHostAsksNothingOfTheUserWhileBlockingADomainSaysWhatChanged() throws {
            let model = try AppModel.test()
            model.actions.blockHost("a.example")
            #expect(model.notices.notice == nil)
        }

        @Test
        func blockingKeepsTheRulesAlreadyThere() throws {
            let model = try AppModel.test()
            model.actions.blockHost("a.example")
            model.actions.blockDomain("b.example")
            #expect(model.settings.blockList.rules.map(\.name) == ["a.example", "b.example"])
        }
    }
}
