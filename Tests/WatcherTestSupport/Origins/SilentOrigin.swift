import Foundation
import NIO

/// Accepts connections and never answers: for timeout tests.
public final class SilentOrigin {
    public let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    public private(set) var port = 0
    private var channel: Channel?

    public init() {}

    public func start() async throws {
        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { $0.pipeline.addHandler(SilentSink()) }
            .bind(host: "127.0.0.1", port: 0).get()
        self.channel = channel
        port = try channel.boundPort()
    }

    public func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}
