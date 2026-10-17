import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct FlowTests {
    @Test
    func sessionsSavedBeforeWebSocketMessagesExistedStillOpen() throws {
        var flow = Flow.fixture(request: .fixture(host: "a.com"), response: nil, state: .pending)
        flow.webSocketMessages = [WebSocketMessage(direction: .clientToServer, kind: .text, payload: Data("x".utf8))]
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(flow)) as? [String: Any])
        object.removeValue(forKey: "webSocketMessages")
        let decoded = try JSONDecoder().decode(Flow.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.webSocketMessages.isEmpty)
    }
}
