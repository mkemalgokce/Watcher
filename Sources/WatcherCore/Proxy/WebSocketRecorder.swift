import Foundation
import NIO

/// Decodes WebSocket frames (RFC 6455) from a relayed byte stream into messages.
/// shortcut: frames over 16 MB stop decoding for that direction.
struct WebSocketFrameParser {
    private static let maxFrameBytes = 16 * 1024 * 1024
    private var buffer: [UInt8] = []
    private var partial: (kind: WebSocketMessage.Kind, payload: Data, compressed: Bool)?
    private var gaveUp = false

    mutating func feed(_ bytes: [UInt8]) -> [(kind: WebSocketMessage.Kind, payload: Data, compressed: Bool)] {
        guard !gaveUp else { return [] }
        buffer += bytes
        var messages: [(kind: WebSocketMessage.Kind, payload: Data, compressed: Bool)] = []

        while buffer.count >= 2 {
            let isFinal = buffer[0] & 0x80 != 0, compressed = buffer[0] & 0x40 != 0, opcode = buffer[0] & 0x0F
            let masked = buffer[1] & 0x80 != 0
            var length = Int(buffer[1] & 0x7F), offset = 2
            if length == 126 {
                guard buffer.count >= 4 else { break }
                length = Int(buffer[2]) << 8 | Int(buffer[3]); offset = 4
            } else if length == 127 {
                guard buffer.count >= 10 else { break }
                let wide = buffer[2 ..< 10].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                guard wide <= UInt64(Self.maxFrameBytes) else { gaveUp = true; buffer = []; break }
                length = Int(wide); offset = 10
            }
            guard length <= Self.maxFrameBytes else { gaveUp = true; buffer = []; break }
            let maskLength = masked ? 4 : 0
            guard buffer.count >= offset + maskLength + length else { break }

            var payload = Array(buffer[(offset + maskLength) ..< (offset + maskLength + length)])
            if masked {
                let key = buffer[offset ..< offset + 4]
                for index in payload.indices {
                    payload[index] ^= key[key.startIndex + index % 4]
                }
            }
            buffer.removeFirst(offset + maskLength + length)

            switch opcode {
            case 0x1, 0x2:
                partial = (opcode == 0x1 ? .text : .binary, Data(payload), compressed)
                if isFinal, let done = partial {
                    messages.append(done); partial = nil
                }
            case 0x0:
                partial?.payload.append(contentsOf: payload)
                if isFinal, let done = partial {
                    messages.append(done); partial = nil
                }
            case 0x8: messages.append((.close, Data(payload), false))
            case 0x9: messages.append((.ping, Data(payload), false))
            case 0xA: messages.append((.pong, Data(payload), false))
            default: break
            }
        }
        return messages
    }
}

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
            store.appendWebSocketMessage(WebSocketMessage(direction: direction, kind: message.kind, payload: payload, isCompressed: stillCompressed), to: flowID)
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
