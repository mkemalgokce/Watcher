import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@Suite(.tags(.unit))
struct FlowSortKeysTests {
    @Test
    func aFlowWithoutAnAnswerSortsBeforeAnyStatusAndAFailureBeforeThat() {
        var pending = Flow.fixture(response: nil)
        pending.state = .pending
        let failed = Flow.fixture(response: nil)
        let answered = Flow.fixture(response: .fixture(status: 200))
        #expect(failed.sortStatus == -1)
        #expect(pending.sortStatus == 0)
        #expect(answered.sortStatus == 200)
        #expect(failed.sortStatus < pending.sortStatus && pending.sortStatus < answered.sortStatus)
    }

    @Test
    func sizeSortsAnEmptyBodyAfterNoResponse() {
        #expect(Flow.fixture(response: nil).sortSize == -1)
        #expect(Flow.fixture(response: .fixture(body: Data())).sortSize == 0)
        #expect(Flow.fixture(response: .fixture(body: Data(count: 7))).sortSize == 7)
    }

    @Test
    func anUnfinishedRequestSortsAsTheLongest() {
        #expect(Flow.fixture(duration: nil).sortDuration == .greatestFiniteMagnitude)
        #expect(Flow.fixture(duration: 0.5).sortDuration == 0.5)
    }

    @Test
    func theAppAndURLAreTheRequestsOwn() {
        #expect(Flow.fixture(request: .fixture(clientApp: nil)).sortApp == "")
        #expect(Flow.fixture(request: .fixture(host: "a.test", path: "/x", clientApp: "Safari")).sortApp == "Safari")
        #expect(Flow.fixture(request: .fixture(host: "a.test", path: "/x")).sortURL == "https://a.test/x")
    }
}
