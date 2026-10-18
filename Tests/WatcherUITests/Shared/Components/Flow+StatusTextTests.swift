import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@Suite(.tags(.unit))
struct FlowStatusTextTests {
    private func flow(_ state: Flow.State, status: Int?) -> Flow {
        .fixture(response: status.map { .fixture(status: $0) }, state: state)
    }

    @Test(arguments: [
        (Flow.State.pending, nil, "…", "Pending", "…"),
        (.failed, nil, "Failed", "Failed", "Failed"),
        (.failed, 502, "Failed", "Failed", "Status 502 Bad Gateway"),
        (.blocked, 403, "403", "403 Forbidden", "Status 403 Forbidden"),
        (.blocked, nil, "—", "—", "—"),
        (.completed, 200, "200", "200 OK", "Status 200 OK"),
        (.completed, nil, "—", "—", "—"),
    ])
    func eachStateReadsTheSameAcrossTheListAndTheInspector(
        state: Flow.State, status: Int?, list: String, inspector: String, spoken: String
    ) {
        let flow = flow(state, status: status)
        #expect(flow.listStatusText == list)
        #expect(flow.inspectorStatusText == inspector)
        #expect(flow.statusAccessibilityLabel == spoken)
    }
}
