import Foundation
import NIO

/// Copies bytes one way between two channels; closes the peer when this side ends.
final class RelayHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private let peer: Channel
    /// Sees every chunk that passes, e.g. to decode WebSocket frames.
    private let tap: (@Sendable (ByteBuffer) -> Void)?
    init(peer: Channel, tap: (@Sendable (ByteBuffer) -> Void)? = nil) {
        self.peer = peer; self.tap = tap
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        tap?(unwrapInboundIn(data))
        peer.writeAndFlush(data, promise: nil)
    }

    func channelInactive(context _: ChannelHandlerContext) {
        peer.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        context.close(promise: nil)
    }
}

extension RelayHandler {
    /// Joins two connections so bytes flow between them untouched, both ways.
    static func join(_ client: Channel, _ upstream: Channel) -> EventLoopFuture<Void> {
        client.pipeline.addHandler(RelayHandler(peer: upstream))
            .flatMap { upstream.pipeline.addHandler(RelayHandler(peer: client)) }
    }
}
