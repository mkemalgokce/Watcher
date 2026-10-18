import NIO

/// Raw TCP origin streaming a chunked event-stream: one event immediately, the next after `delay`.
public final class StreamOrigin {
    public let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    public let delay: TimeAmount
    public private(set) var port = 0
    private var channel: Channel?

    public init(delay: TimeAmount = .milliseconds(1200)) {
        self.delay = delay
    }

    public func start() async throws {
        let delay = delay
        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { $0.pipeline.addHandler(StreamHandler(delay: delay)) }
            .bind(host: "127.0.0.1", port: 0).get()
        self.channel = channel
        port = try channel.boundPort()
    }

    public func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}
