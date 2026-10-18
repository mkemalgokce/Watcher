import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Requests paused at a breakpoint: how they are announced, which rules they belong to and how they are let go.
@MainActor
@Suite(.tags(.unit))
struct BreakpointsViewModelTests {
    private let center = BreakpointCenter()
    private let notices = NoticeCenter.silent()
    private let settings = SettingsEditor.inMemory()

    private func viewModel() -> BreakpointsViewModel {
        BreakpointsViewModel(center: center, settings: settings, notices: notices)
    }

    private func hit(_ path: String) -> BreakpointCenter.Hit {
        .init(phase: .request, request: .fixture(path: path))
    }

    private func useRules(_ names: [String: String]) {
        settings.breakpoints = RuleSet(isEnabled: true, rules: names.sorted { $0.key < $1.key }.map {
            BreakpointRule(name: $0.key, matching: MatchingRule(pattern: $0.value))
        })
    }

    /// Pauses a request in the real center and returns what it was resolved with.
    private func pause(_ path: String) -> Task<BreakpointCenter.Resolution, Never> {
        let center = center
        return Task { await center.hold(phase: .request, request: .fixture(path: path)) }
    }

    @Test
    func newPausesAreAnnouncedNotOpened() {
        let breakpoints = viewModel()
        breakpoints.changed([hit("/a")])
        #expect(notices.notice?.message == "1 paused at a breakpoint. Review with ⌘B, or remove the breakpoint there.")
        notices.dismiss()
        breakpoints.changed([])
        #expect(notices.notice == nil, "a resolved pause is not announced")
        #expect(breakpoints.hits.isEmpty)
    }

    @Test
    func aNewPauseIsAnnouncedEvenWhenAnotherWasReleasedInTheSameChange() {
        let breakpoints = viewModel()
        let first = hit("/a"), second = hit("/b")
        breakpoints.changed([first])
        notices.dismiss()
        breakpoints.changed([second])
        #expect(notices.notice?.message == "1 paused at a breakpoint. Review with ⌘B, or remove the breakpoint there.")
        #expect(breakpoints.hits.map(\.id) == [second.id])
    }

    @Test
    func releasingSomePausesAnnouncesNothing() {
        let breakpoints = viewModel()
        let first = hit("/a"), second = hit("/b")
        breakpoints.changed([first, second])
        notices.dismiss()
        breakpoints.changed([second])
        breakpoints.changed([second])
        #expect(notices.notice == nil)
    }

    @Test
    func theListFollowsTheCenter() async {
        let breakpoints = viewModel()
        breakpoints.observe()
        let paused = pause("/a")
        #expect(await eventually { breakpoints.hits.count == 1 })
        breakpoints.continueAll()
        _ = await paused.value
        #expect(await eventually { breakpoints.hits.isEmpty })
    }

    @Test
    func rulesMatchingAPausedRequest() {
        let breakpoints = viewModel()
        settings.breakpoints = RuleSet(isEnabled: true, rules: [
            BreakpointRule(name: "login", matching: MatchingRule(pattern: "api.example.com/login")),
            BreakpointRule(name: "off", isEnabled: false, matching: MatchingRule(pattern: "api.example.com/login")),
            BreakpointRule(name: "other", matching: MatchingRule(pattern: "other.example.com/*")),
        ])
        #expect(breakpoints.rules(matching: hit("/login").request).map(\.name) == ["login"])
        #expect(breakpoints.rules(matching: hit("/elsewhere").request).isEmpty)
    }

    @Test
    func removingTheBreakpointOfAPausedRequest() {
        let breakpoints = viewModel()
        useRules(["login": "api.example.com/login", "keep": "api.example.com/keep"])
        breakpoints.removeBreakpoints(for: hit("/login"))
        #expect(settings.breakpoints.rules.map(\.name) == ["keep"])
        #expect(notices.notice?.message == "Breakpoint “login” removed")
    }

    @Test
    func removingSeveralRulesSaysHowMany() {
        let breakpoints = viewModel()
        useRules(["a": "api.example.com/*", "b": "api.example.com/login"])
        breakpoints.removeBreakpoints(for: hit("/login"))
        #expect(settings.breakpoints.rules.isEmpty)
        #expect(notices.notice?.message == "2 breakpoints removed")
    }

    @Test
    func removingWhenNoRuleMatchesOnlyLetsTheRequestGo() async {
        let breakpoints = viewModel()
        useRules(["keep": "api.example.com/keep"])
        let paused = pause("/nothing")
        #expect(await eventually { center.pending.count == 1 })
        breakpoints.removeBreakpoints(for: center.pending[0])
        guard case .proceed = await paused.value else {
            Issue.record("the request was not let through")
            return
        }
        #expect(settings.breakpoints.rules.map(\.name) == ["keep"])
    }

    @Test
    func removingARuleLetsGoEverythingNoOtherRuleStops() async {
        let breakpoints = viewModel()
        useRules(["login": "api.example.com/login", "keep": "api.example.com/keep"])
        let login = pause("/login"), kept = pause("/keep")
        #expect(await eventually { center.pending.count == 2 })
        breakpoints.changed(center.pending)
        breakpoints.removeBreakpoints(for: hit("/login"))
        guard case .proceed = await login.value else {
            Issue.record("the login request still hangs")
            return
        }
        #expect(center.pending.map(\.request.path) == ["/keep"], "a request another rule stops stays paused")
        breakpoints.abortAll()
        guard case .abort = await kept.value else {
            Issue.record("abort all did not abort")
            return
        }
    }

    @Test
    func continueAndAbortAllSaySo() async {
        let breakpoints = viewModel()
        let first = pause("/a")
        #expect(await eventually { center.pending.count == 1 })
        breakpoints.continueAll()
        #expect(notices.notice?.message == "All paused traffic continued")
        guard case .proceed = await first.value else {
            Issue.record("not continued")
            return
        }
        let second = pause("/b")
        #expect(await eventually { center.pending.count == 1 })
        breakpoints.abortAll()
        #expect(notices.notice?.message == "All paused traffic aborted")
        guard case .abort = await second.value else {
            Issue.record("not aborted")
            return
        }
    }
}
