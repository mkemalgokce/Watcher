import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension AppModelTests {
    /// Requests paused at a breakpoint: how they are announced and which rules they belong to.
    @MainActor
    struct Breakpoints {
        private func hit(_ path: String) -> BreakpointCenter.Hit {
            .init(phase: .request, request: .fixture(path: path))
        }

        @Test
        func newPausesAreAnnouncedNotOpened() {
            let model = AppModel(listening: false)
            model.breakpointsChanged([hit("/a")])
            #expect(model.sheet == nil, "a pause must never take over the window")
            #expect(model.notices.notice?.kind == .info)
            model.notices.dismiss()
            model.breakpointsChanged([])
            #expect(model.notices.notice == nil, "a resolved pause is not announced")
        }

        @Test
        func rulesMatchingAPausedRequest() {
            let model = AppModel(listening: false)
            model.settings.breakpoints = RuleSet(isEnabled: true, rules: [
                BreakpointRule(name: "login", matching: MatchingRule(pattern: "api.example.com/login")),
                BreakpointRule(name: "off", isEnabled: false, matching: MatchingRule(pattern: "api.example.com/login")),
                BreakpointRule(name: "other", matching: MatchingRule(pattern: "other.example.com/*")),
            ])
            #expect(
                model.breakpointRules(matching: hit("/login").request).map(\.name) == ["login"],
                "disabled and unrelated rules are ignored"
            )
            #expect(model.breakpointRules(matching: hit("/elsewhere").request).isEmpty)
        }

        @Test
        func removingTheBreakpointOfAPausedRequest() {
            let model = AppModel(listening: false)
            model.settings.breakpoints = RuleSet(isEnabled: true, rules: [
                BreakpointRule(name: "login", matching: MatchingRule(pattern: "api.example.com/login")),
                BreakpointRule(name: "keep", matching: MatchingRule(pattern: "api.example.com/keep")),
            ])
            model.removeBreakpoints(for: hit("/login"))
            #expect(model.settings.breakpoints.rules.map(\.name) == ["keep"])
            #expect(model.notices.notice?.message == "Breakpoint “login” removed")
            // Removing for a request no rule matches only lets it continue and leaves the rules alone.
            model.removeBreakpoints(for: hit("/nothing"))
            #expect(model.settings.breakpoints.rules.map(\.name) == ["keep"])
        }
    }
}
