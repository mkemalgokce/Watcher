import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct BreakpointsTests {
        @Test
        func breakpointRulesCanBeDeletedFromTheWindow() async throws {
            let model = try AppModel.demo()
            model.settings.breakpoints = RuleSet(isEnabled: true, rules: [
                BreakpointRule(name: "Login", matching: MatchingRule(pattern: "api.example.com/v1/login")),
                BreakpointRule(name: "Users", matching: MatchingRule(pattern: "*/v1/users*")),
            ])
            try await withWindow(showing: BreakpointsView().environment(model), width: 900, height: 560) { window in
                #expect(await eventually { window.elements("Delete Breakpoint").count == 2 })

                try await window.press("Delete Breakpoint")
                #expect(model.settings.breakpoints.rules.map(\.name) == ["Users"])
                #expect(model.notices.notice?.message == "Breakpoint “Login” removed")
                #expect(
                    await eventually { window.elements("Delete Breakpoint").count == 1 },
                    "the list redraws without the deleted rule"
                )
            }
        }

        @Test
        func pausedRequestCanBeContinuedAndItsBreakpointRemoved() async throws {
            let model = try AppModel.demo()
            let request = RequestRecord.fixture(method: "POST", path: "/v1/login")
            model.settings.breakpoints = RuleSet(isEnabled: true, rules: [
                BreakpointRule(name: "Login", matching: MatchingRule(pattern: "api.example.com/v1/login")),
            ])
            model.breakpoints.hits = [.init(phase: .request, request: request)]
            try await withWindow(showing: BreakpointsView().environment(model), width: 900, height: 600) { window in
                try await window.press("Remove Breakpoint")
                #expect(model.settings.breakpoints.rules.isEmpty, "the rule that kept pausing is gone")
                #expect(model.router.sheet == nil, "nothing else was opened")
            }
        }
    }
}
