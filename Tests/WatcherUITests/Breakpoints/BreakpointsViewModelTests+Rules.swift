import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension BreakpointsViewModelTests {
    /// Editing and deleting the rules listed in the Breakpoints window, which may be redrawn after the list changed.
    @MainActor
    struct Rules {
        private let notices = NoticeCenter.silent()
        private let settings = SettingsEditor.inMemory()
        private let login = BreakpointRule(name: "login", matching: MatchingRule(pattern: "*/login"))
        private let users = BreakpointRule(matching: MatchingRule(pattern: "*/users"))

        private func viewModel() -> BreakpointsViewModel {
            settings.breakpoints = RuleSet(isEnabled: true, rules: [login, users])
            return BreakpointsViewModel(center: BreakpointCenter(), settings: settings, notices: notices)
        }

        @Test
        func anEditReplacesTheRuleAtItsRow() {
            let breakpoints = viewModel()
            var edited = users
            edited.onResponse = false
            breakpoints.updateRule(at: 1, to: edited)
            #expect(settings.breakpoints.rules == [login, edited])
        }

        @Test(arguments: [-1, 2, 10])
        func anEditToARowThatIsGoneChangesNothing(index: Int) {
            let breakpoints = viewModel()
            breakpoints.updateRule(at: index, to: BreakpointRule(matching: MatchingRule(pattern: "*")))
            #expect(settings.breakpoints.rules == [login, users])
        }

        @Test
        func deletingARuleRemovesItAndSaysWhichOne() {
            let breakpoints = viewModel()
            breakpoints.removeRule(users, at: 1)
            #expect(settings.breakpoints.rules == [login])
            #expect(notices.notice?.message == "Breakpoint “*/users” removed")
            #expect(notices.notice?.kind == .success)
        }

        @Test(arguments: [0, 2, -1])
        func aDeleteFromAStaleRowLeavesTheOtherRulesAlone(index: Int) {
            let breakpoints = viewModel()
            breakpoints.removeRule(users, at: index)
            #expect(settings.breakpoints.rules == [login, users])
            #expect(notices.notice == nil)
        }

        @Test
        func removingTheBreakpointOfAPausedRequestKeepsADisabledRuleWithTheSameNameAndPattern() {
            let breakpoints = viewModel()
            var parked = login
            parked.isEnabled = false
            settings.breakpoints.rules.append(parked)
            let hit = BreakpointCenter.Hit(phase: .request, request: .fixture(path: "/login"))
            breakpoints.removeBreakpoints(for: hit)
            #expect(settings.breakpoints.rules == [users, parked])
        }
    }

    /// What the Breakpoints window decides from the paused list: which row stays selected and how long it has waited.
    @MainActor
    struct Window {
        private let first = UUID(), second = UUID()

        @Test(arguments: [(0, 0), (1, 1), (2, 0)])
        func theSelectionStaysWhileItsHitIsPausedAndOtherwiseFallsToTheFirst(selected: Int, expected: Int) {
            let ids = [first, second]
            let current: UUID? = selected == 2 ? UUID() : ids[selected]
            #expect(BreakpointsViewModel.selection(keeping: current, among: ids) == ids[expected])
        }

        @Test
        func withNothingSelectedTheFirstIsChosenAndWithNothingPausedNothingIs() {
            #expect(BreakpointsViewModel.selection(keeping: nil, among: [first, second]) == first)
            #expect(BreakpointsViewModel.selection(keeping: first, among: []) == nil)
        }

        @Test(arguments: [
            (0, "Paused for 0 s", false), (19, "Paused for 19 s", false),
            (20, "Paused for 20 s. The client may give up soon; continue or abort.", true),
            (95, "Paused for 95 s. The client may give up soon; continue or abort.", true),
        ])
        func theWaitWarnsFromTwentySeconds(seconds: Int, text: String, late: Bool) {
            let start = Date(timeIntervalSinceReferenceDate: 1000)
            let hit = BreakpointCenter.Hit(phase: .request, request: .fixture(), pausedAt: start)
            let wait = BreakpointsViewModel.wait(of: hit, at: start.addingTimeInterval(Double(seconds) + 0.9))
            #expect(wait.text == text)
            #expect(wait.isLate == late)
        }

        @Test
        func aClockBehindThePauseNeverShowsANegativeWait() {
            let start = Date(timeIntervalSinceReferenceDate: 1000)
            let hit = BreakpointCenter.Hit(phase: .request, request: .fixture(), pausedAt: start)
            #expect(BreakpointsViewModel.wait(of: hit, at: start.addingTimeInterval(-30)).text == "Paused for 0 s")
        }
    }
}
