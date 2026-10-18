import Foundation
import NIO

final class UpgradeEcho: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private var upgraded = false
    private var pending = Data()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if upgraded {
            return write(context, buffer)
        }
        pending.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? [])
        guard pending.range(of: Data("\r\n\r\n".utf8)) != nil else { return }
        upgraded = true
        let answer = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
        write(context, context.channel.allocator.buffer(string: answer))
    }

    private func write(_ context: ChannelHandlerContext, _ buffer: ByteBuffer) {
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }
}
