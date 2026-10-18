import Foundation
import NIO
import NIOHTTP1

/// The channel handlers every kind of client connection is built from.
extension ProxyServer {
    /// The plain HTTP/1.1 handlers of one client connection, in pipeline order.
    struct HTTP1Pipeline {
        let encoder: HTTPResponseEncoder
        let decoder: ByteToMessageHandler<HTTPRequestDecoder>
        let handler: ProxyConnectionHandler

        var handlers: [RemovableChannelHandler] {
            [encoder, decoder, handler]
        }
    }

    /// A request decoder that hands the bytes after a CONNECT or an upgrade on untouched.
    static func requestDecoder() -> ByteToMessageHandler<HTTPRequestDecoder> {
        ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
    }

    func http1Pipeline(
        origin: ReverseOrigin? = nil,
        tunnel: TunnelTarget? = nil,
        details: ConnectionDetails = ConnectionDetails()
    ) -> HTTP1Pipeline {
        let encoder = HTTPResponseEncoder(), decoder = Self.requestDecoder()
        let handler = ProxyConnectionHandler(
            server: self, codecs: [encoder, decoder], origin: origin, tunnel: tunnel, details: details
        )
        return HTTP1Pipeline(encoder: encoder, decoder: decoder, handler: handler)
    }

    /// Connects to `host` (after DNS Spoofing) for a tunnel that is relayed without being decrypted.
    func connectBlind(to host: String, port: Int, on loop: EventLoop) -> EventLoopFuture<Channel> {
        ClientBootstrap(group: loop).connect(host: resolve(host), port: port)
    }
}
