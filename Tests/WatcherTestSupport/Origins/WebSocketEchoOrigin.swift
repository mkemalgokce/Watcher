import NIO

/// A real RFC 6455 echo server: completes the handshake (Sec-WebSocket-Accept) and answers each text frame with the same text.
public final class WebSocketEchoOrigin {
    public let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    public private(set) var port = 0
    private var channel: Channel?

    public init() {}

    public func start() async throws {
        let channel = try await ServerBootstrap(group: group)
            .childChannelInitializer { $0.pipeline.addHandler(WebSocketEcho()) }
            .bind(host: "127.0.0.1", port: 0).get()
        self.channel = channel
        port = try channel.boundPort()
    }

    public func stop() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }
}
