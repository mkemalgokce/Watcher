import Foundation
import NIO

/// Feeds both directions of a tunnelled WebSocket into the flow's message list.
final class WebSocketRecorder: @unchecked Sendable {
    private let store: FlowStore
    private let flowID: Flow.ID
    private let lock = NSLock()
    private var clientParser = WebSocketFrameParser()
    private var serverParser = WebSocketFrameParser()
    private var serverHandshake = Data()
    private var serverHandshakeDone = false
    /// One window per direction, shared by every compressed message (context takeover).
    private var inflaters: [WebSocketMessage.Direction: RawInflater] = [:]

    init(store: FlowStore, flowID: Flow.ID) {
        self.store = store; self.flowID = flowID
    }

    func record(_ buffer: ByteBuffer, direction: WebSocketMessage.Direction) {
        var buffer = buffer
        var bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        let messages: [(kind: WebSocketMessage.Kind, payload: Data, compressed: Bool)] = lock.withLock {
            if direction == .clientToServer {
                return clientParser.feed(bytes)
            }
            // The upstream's first bytes are its HTTP 101 response, not frames.
            if !serverHandshakeDone {
                serverHandshake.append(contentsOf: bytes)
                guard let end = serverHandshake.range(of: Data("\r\n\r\n".utf8)) else { return [] }
                bytes = Array(serverHandshake[end.upperBound...])
                serverHandshakeDone = true; serverHandshake = Data()
            }
            return serverParser.feed(bytes)
        }
        for message in messages {
            var payload = message.payload, stillCompressed = message.compressed
            if message.compressed, let inflated = inflate(payload, direction: direction) {
                payload = inflated; stillCompressed = false
            }
            let recorded = WebSocketMessage(
                direction: direction, kind: message.kind, payload: payload, isCompressed: stillCompressed
            )
            store.appendWebSocketMessage(recorded, to: flowID)
        }
    }

    /// permessage-deflate: the sender drops the sync-flush tail, so it is put back before inflating.
    private func inflate(_ payload: Data, direction: WebSocketMessage.Direction) -> Data? {
        lock.withLock {
            let inflater = inflaters[direction] ?? RawInflater()
            inflaters[direction] = inflater
            return inflater.inflate(payload + Data([0x00, 0x00, 0xFF, 0xFF]))
        }
    }
}
