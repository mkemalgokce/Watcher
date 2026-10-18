import Foundation
import Testing
import WatcherCore
@testable import WatcherUI

@Suite(.tags(.unit))
struct WebSocketMessageListTests {
    private func message(_ kind: WebSocketMessage.Kind) -> WebSocketMessage {
        WebSocketMessage(direction: .clientToServer, kind: kind, payload: Data())
    }

    private var mixed: [WebSocketMessage] {
        [message(.text), message(.ping), message(.pong), message(.binary), message(.close)]
    }

    @Test
    func pingAndPongFramesCanBeHidden() {
        let list = WebSocketMessageList(all: mixed, hidesPingPong: true)
        #expect(list.shown.map(\.kind) == [.text, .binary, .close])
        #expect(list.countText == "3 of 5 messages")
        #expect(WebSocketMessageList(all: mixed, hidesPingPong: false).shown.count == 5)
    }

    @Test(arguments: [
        ([WebSocketMessage.Kind](), "The socket has not sent anything yet."),
        ([.ping, .pong], "Only ping/pong frames so far."),
    ])
    func theEmptyTextSaysWhetherAnythingWasSent(kinds: [WebSocketMessage.Kind], text: String) {
        let list = WebSocketMessageList(all: kinds.map(message), hidesPingPong: true)
        #expect(list.shown.isEmpty)
        #expect(list.emptyText == text)
    }
}
