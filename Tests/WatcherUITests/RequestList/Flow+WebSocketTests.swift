import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@Suite(.tags(.unit))
struct FlowWebSocketTests {
    @Test(arguments: [(101, true), (200, false), (nil, false)])
    func anUpgradeAnswerIsAWebSocket(status: Int?, expected: Bool) {
        #expect(Flow.fixture(sequence: 1, status: status).isWebSocket == expected)
    }

    @Test
    func messagesMakeAWebSocketWhateverTheStatus() {
        var flow = Flow.fixture(sequence: 1, status: 200)
        let message = WebSocketMessage(
            direction: .clientToServer, kind: .text, payload: Data("hi".utf8), date: .distantPast
        )
        flow.webSocketMessages = [message]
        #expect(flow.isWebSocket)
    }
}
