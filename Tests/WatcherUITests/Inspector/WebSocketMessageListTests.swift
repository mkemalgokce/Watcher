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

@Suite(.tags(.unit))
struct WebSocketJSONMessageTests {
    private func message(_ kind: WebSocketMessage.Kind, _ text: String, compressed: Bool = false) -> WebSocketMessage {
        WebSocketMessage(direction: .serverToClient, kind: kind, payload: Data(text.utf8), isCompressed: compressed)
    }

    @Test
    func aTextFrameWithJSONCanBeOpened() {
        let frame = #"{"type":"tick","n":1}"#
        #expect(WebSocketMessageList.jsonText(of: message(.text, frame)) == frame)
    }

    @Test
    func someServersSendJSONInBinaryFrames() {
        #expect(WebSocketMessageList.jsonText(of: message(.binary, "[1,2]")) == "[1,2]")
    }

    @Test(arguments: [
        (WebSocketMessage.Kind.text, "hello", false), (.text, "{broken", false), (.text, "42", false),
        (.ping, #"{"a":1}"#, false), (.pong, #"{"a":1}"#, false), (.close, #"{"a":1}"#, false),
        (.text, #"{"a":1}"#, true),
    ])
    func everythingElseIsLeftAsText(kind: WebSocketMessage.Kind, text: String, compressed: Bool) {
        #expect(WebSocketMessageList.jsonText(of: message(kind, text, compressed: compressed)) == nil)
    }
}
