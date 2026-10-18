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

    private static let handshake = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n"
    private static let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private let store = FlowStore(now: { WebSocketRecorderTests.recordedAt })
    private let allocator = ByteBufferAllocator()

    private func recorder() -> WebSocketRecorder {
        let flow = store.begin(.fixture(scheme: "http", host: "a", port: 80))
        return WebSocketRecorder(store: store, flowID: flow.id)
    }

    private func buffer(_ bytes: [UInt8]) -> ByteBuffer {
        allocator.buffer(bytes: bytes)
    }

    private func messages() throws -> [WebSocketMessage] {
        try #require(store.all.first).webSocketMessages
    }

    /// A text frame; clients mask their payloads, servers do not.
    private func textFrame(_ text: String, masked: Bool = false, rsv1: Bool = false) -> [UInt8] {
        let payload = Array(text.utf8)
        let first: UInt8 = rsv1 ? 0xC1 : 0x81
        return masked
            ? [first, 0x80 | UInt8(payload.count), 0, 0, 0, 0] + payload
            : [first, UInt8(payload.count)] + payload
    }

    @Test
    func aMessageIsDatedByTheStoresClock() throws {
        let recorder = recorder()
        recorder.record(buffer(textFrame("hi", masked: true)), direction: .clientToServer)
        #expect(try messages().map(\.date) == [Self.recordedAt])
    }

    @Test
    func aHandshakeSplitAcrossReadsIsSkippedWhole() throws {
        let recorder = recorder()
        let bytes = Array(Self.handshake.utf8)
        recorder.record(buffer(Array(bytes.prefix(20))), direction: .serverToClient)
        recorder.record(buffer(Array(bytes.dropFirst(20)) + textFrame("hi")), direction: .serverToClient)
        #expect(try messages().map { String(bytes: $0.payload, encoding: .utf8) } == ["hi"])
    }

    @Test
    func framesInTheSameReadAsTheEndOfTheHandshakeAreRecorded() throws {
        let recorder = recorder()
        let bytes = Array(Self.handshake.utf8) + textFrame("one") + textFrame("two")
        recorder.record(buffer(bytes), direction: .serverToClient)
        #expect(try messages().map { String(bytes: $0.payload, encoding: .utf8) } == ["one", "two"])
    }

    @Test
    func aCompressedMessageThatCannotBeInflatedStaysMarkedCompressed() throws {
        let recorder = recorder()
        recorder.record(buffer(Array(Self.handshake.utf8)), direction: .serverToClient)
        let damaged = Array(RawInflaterTests.corrupt)
        recorder.record(buffer([0xC1, UInt8(damaged.count)] + damaged), direction: .serverToClient)
        let message = try #require(messages().first)
        #expect(message.isCompressed)
        #expect(message.payload == RawInflaterTests.corrupt)
    }

    @Test
    func onlyTheNewestMessagesOfAChattySocketAreKept() throws {
        let recorder = recorder()
        let limit = FlowStore.maxWebSocketMessages
        for number in 0 ..< limit + 5 {
            recorder.record(buffer(textFrame("m\(number)", masked: true)), direction: .clientToServer)
        }
        let kept = try messages()
        #expect(kept.count == limit)
        #expect(String(bytes: kept[0].payload, encoding: .utf8) == "m5")
    }
}
