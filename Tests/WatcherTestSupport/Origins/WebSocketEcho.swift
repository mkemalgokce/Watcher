import CryptoKit
import Foundation
import NIO
@testable import WatcherCore

final class WebSocketEcho: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private static let acceptGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    private var parser = WebSocketFrameParser()
    private var pending = Data()
    private var upgraded = false

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        guard upgraded else {
            pending.append(contentsOf: bytes)
            guard let end = pending.range(of: Data("\r\n\r\n".utf8)) else { return }
            upgraded = true
            let accept = Self.accept(forHandshake: pending[..<end.lowerBound])
            let answer = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                + "Sec-WebSocket-Accept: \(accept)\r\n\r\n"
            send(context, Array(answer.utf8))
            echo(context, Array(pending[end.upperBound...]))
            return
        }
        echo(context, bytes)
    }

    private static func accept(forHandshake head: Data) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: head, as: UTF8.self)
        let key = text.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("sec-websocket-key:") }?
            .dropFirst("sec-websocket-key:".count).trimmingCharacters(in: .whitespaces) ?? ""
        return Data(Insecure.SHA1.hash(data: Data((key + acceptGUID).utf8))).base64EncodedString()
    }

    private func echo(_ context: ChannelHandlerContext, _ bytes: [UInt8]) {
        for message in parser.feed(bytes) where message.kind == .text && message.payload.count < 126 {
            send(context, [0x81, UInt8(message.payload.count)] + Array(message.payload))
        }
    }

    private func send(_ context: ChannelHandlerContext, _ bytes: [UInt8]) {
        context.writeAndFlush(wrapOutboundOut(context.channel.allocator.buffer(bytes: bytes)), promise: nil)
    }
}
