import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension BreakpointsViewModelTests {
    /// Editing and deleting the rules listed in the Breakpoints window, which may be redrawn after the list changed.
    @MainActor
    struct Rules {
        private let notices = NoticeCenter(sleep: sleepUntilCancelled) { _ in }
        private let settings = SettingsEditor(
            initial: WatcherSettings(), sleep: sleepUntilCancelled,
            notices: NoticeCenter(sleep: sleepUntilCancelled) { _ in }, persist: { _ in }, apply: { _ in }
        )
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
    }
}
