import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Dialogs, focus requests and the Compare window.
@MainActor
@Suite(.tags(.unit))
struct WindowRouterTests {
    private let notices = NoticeCenter(sleep: sleepUntilCancelled) { _ in }

    @Test(arguments: [WindowRouter.Sheet.tools, .breakpoints, .compose, .devices, .welcome, .converter, .help])
    func showOpensTheSheet(sheet: WindowRouter.Sheet) {
        let router = WindowRouter(notices: notices) {}
        router.show(sheet)
        #expect(router.sheet == sheet)
        #expect(sheet.id == sheet)
    }

    @Test
    func eachSearchFocusRequestCountsAndFocusesTheField() {
        var focused = 0
        let router = WindowRouter(notices: notices) { focused += 1 }
        router.requestSearchFocus()
        router.requestSearchFocus()
        #expect(router.searchFocusRequest == 2)
        #expect(focused == 2)
    }

    @Test
    func composeOpensWithTheDraftAndItsSource() {
        let router = WindowRouter(notices: notices) {}
        let flow = Flow.fixture()
        router.compose(flow.request, from: flow)
        #expect(router.sheet == .compose)
        #expect(router.composeDraft == flow.request)
        #expect(router.composeSource?.id == flow.id)
    }

    @Test
    func compareRemembersTheBaseAndBringsTheWindowForward() {
        let router = WindowRouter(notices: notices) {}
        let base = Flow.fixture(sequence: 7, status: 200)
        router.compare(withBase: base)
        router.compare(withBase: base)
        #expect(router.diffBase?.id == base.id)
        #expect(router.compareWindowRequest == 2)
        #expect(notices.notice?.message == "#7 is the compare base. Select another request to compare.")
    }
}
