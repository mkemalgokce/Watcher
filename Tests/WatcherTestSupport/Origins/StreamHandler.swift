import Foundation
import NIO

final class StreamHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private let delay: TimeAmount
    private var pending = Data()
    private var started = false

    init(delay: TimeAmount) {
        self.delay = delay
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        pending.append(contentsOf: buffer.readBytes(length: buffer.readableBytes) ?? [])
        guard !started, pending.range(of: Data("\r\n\r\n".utf8)) != nil else { return }
        started = true
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n"
        send(context, head + "b\r\ndata: one\n\n\r\n")
        let loop = context.eventLoop
        let channel = context.channel
        loop.scheduleTask(in: delay) {
            channel.writeAndFlush(channel.allocator.buffer(string: "b\r\ndata: two\n\n\r\n0\r\n\r\n"), promise: nil)
        }
    }

    private func send(_ context: ChannelHandlerContext, _ text: String) {
        context.writeAndFlush(wrapOutboundOut(context.channel.allocator.buffer(string: text)), promise: nil)
    }
}
