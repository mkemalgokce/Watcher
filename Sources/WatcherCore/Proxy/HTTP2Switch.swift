import Foundation
import NIO
import NIOHTTP2
import NIOSSL
import NIOTLS

/// Lets decrypted connections speak HTTP/2 to the client when it offers it (ALPN `h2`); everything else stays HTTP/1.1.
extension ProxyServer {
    /// TLS plus the ALPN switch, in pipeline order. `http1` are the handlers to drop if `h2` wins.
    func tlsHandlers(host: String, http1: [RemovableChannelHandler], details: ConnectionDetails) throws -> [ChannelHandler] {
        guard authority != nil || hasCustomServerCertificate(for: host) else { return [] }
        return try [NIOSSLServerHandler(context: serverContext(for: host)), http2Switch(host: host, port: 443, http1: http1, details: details)]
    }

    func http2Switch(host: String, port: Int, http1: [RemovableChannelHandler], details: ConnectionDetails) -> ApplicationProtocolNegotiationHandler {
        ApplicationProtocolNegotiationHandler { [self] result, channel in
            var protocolName = "http/1.1"
            if case let .negotiated(name) = result {
                protocolName = name
            }
            let version = (try? channel.pipeline.syncOperations.handler(type: NIOSSLServerHandler.self).tlsVersion).flatMap(\.self)
            details.record(tlsVersion: version.map(Self.format), alpn: protocolName)
            guard protocolName == "h2" else { return channel.eventLoop.makeSucceededVoidFuture() }
            let removals = http1.map { channel.pipeline.removeHandler($0) }
            return EventLoopFuture.andAllSucceed(removals, on: channel.eventLoop).flatMap {
                // Each HTTP/2 stream is its own channel and gets its own copy of the normal request handler.
                channel.configureHTTP2Pipeline(mode: .server) { stream in
                    stream.pipeline.addHandlers([
                        HTTP2FramePayloadToHTTP1ServerCodec(),
                        ProxyConnectionHandler(
                            server: self,
                            codecs: [],
                            origin: nil,
                            tunnel: TunnelTarget(scheme: "https", host: host, port: port),
                            isHTTP2: true,
                            details: details
                        ),
                    ])
                }.map { _ in () }
            }
        }
    }

    private static func format(_ version: TLSVersion) -> String {
        switch version {
        case .tlsv1: "TLS 1.0"
        case .tlsv11: "TLS 1.1"
        case .tlsv12: "TLS 1.2"
        case .tlsv13: "TLS 1.3"
        }
    }
}
