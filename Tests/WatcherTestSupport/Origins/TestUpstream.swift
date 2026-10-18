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

    public init(tls: NIOSSLContext? = nil) {
        self.tls = tls
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
            .bind(host: "127.0.0.1", port: 0).get()
        self.channel = channel
        port = try channel.boundPort()
    }

    public func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}
