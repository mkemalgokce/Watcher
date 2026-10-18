import Foundation
import NIO
import NIOHTTP1

/// Tiny HTTP origin that echoes what it received.
public final class TestUpstream {
    public let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    public private(set) var port = 0
    private var channel: Channel?

    public init() {}

    public func start() async throws {
        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap { channel.pipeline.addHandler(EchoHandler()) }
            }
            .bind(host: "127.0.0.1", port: 0).get()
        self.channel = channel
        port = try channel.boundPort()
    }

    public func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}
