import Foundation
import NIO
import NIOHTTP1
import NIOSSL

/// Tiny HTTP origin that echoes what it received; with `tls` it speaks HTTPS with that certificate.
public final class TestUpstream {
    public let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    public private(set) var port = 0
    private var channel: Channel?
    private let tls: NIOSSLContext?
    private let bindHost: String

    /// `bindHost` is the loopback address the origin listens on: `::1` for an IPv6 origin.
    public init(tls: NIOSSLContext? = nil, bindHost: String = "127.0.0.1") {
        self.tls = tls
        self.bindHost = bindHost
    }

    public func start() async throws {
        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { [tls] channel in
                let encrypted = tls.map { channel.pipeline.addHandler(NIOSSLServerHandler(context: $0)) }
                    ?? channel.eventLoop.makeSucceededVoidFuture()
                return encrypted
                    .flatMap { channel.pipeline.configureHTTPServerPipeline() }
                    .flatMap { channel.pipeline.addHandler(EchoHandler()) }
            }
            .bind(host: bindHost, port: 0).get()
        self.channel = channel
        port = try channel.boundPort()
    }

    public func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}
