import Foundation
import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct WebSocketRecorderTests {
    @Test
    func permessageDeflateKeepsTheWindowBetweenMessages() throws {
        // Produced by Python: zlib.compressobj(wbits=-15) with Z_SYNC_FLUSH after each message, tail 00 00 FF FF removed.
        let first = Data(hex: "ca48cdc9c957c840270100"), second = Data(hex: "421628cf2fca4981b00100")
        let store = FlowStore()
        let flow = store.begin(RequestRecord.fixture(scheme: "http", host: "a", port: 80))
        let recorder = WebSocketRecorder(store: store, flowID: flow.id)

        func frame(_ payload: Data) -> ByteBuffer { // server -> client: FIN + RSV1 + text, unmasked
            ByteBufferAllocator().buffer(bytes: [0xC1, UInt8(payload.count)] + Array(payload))
        }
        recorder.record(
            ByteBufferAllocator().buffer(string: "HTTP/1.1 101 Switching Protocols\r\n\r\n"),
            direction: .serverToClient
        )
        recorder.record(frame(first), direction: .serverToClient)
        recorder.record(frame(second), direction: .serverToClient)

        let messages = try #require(store.all.first).webSocketMessages
        #expect(
            messages.map { String(bytes: $0.payload, encoding: .utf8) }
                == ["hello hello hello hello", "hello hello world hello"]
        )
        #expect(messages.map(\.isCompressed) == [false, false])
    }
}
