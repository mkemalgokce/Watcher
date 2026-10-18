import NIO

final class SilentSink: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    func channelRead(context _: ChannelHandlerContext, data _: NIOAny) {}
}
