import Foundation
import NIO

/// Raw TCP client that accumulates whatever it receives.
public final class RawClient {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let sink = ByteSink()
    private var channel: Channel?

    public init() {}

    public func connect(port: Int) async throws {
        channel = try await ClientBootstrap(group: group)
            .channelInitializer { [sink] in $0.pipeline.addHandler(sink) }
            .connect(host: "127.0.0.1", port: port).get()
    }

    public func send(_ text: String) async throws {
        let channel = try connected()
        try await channel.writeAndFlush(channel.allocator.buffer(string: text))
    }

    public func send(bytes: [UInt8]) async throws {
        let channel = try connected()
        try await channel.writeAndFlush(channel.allocator.buffer(bytes: bytes))
    }

    public func receivedBytes(atLeast count: Int, timeout: TimeInterval = 5) async -> [UInt8] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, sink.raw.count < count {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return sink.raw
    }

    public func received(containing needle: String, timeout: TimeInterval = 5) async -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = sink.text
            if text.contains(needle) {
                return text
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return sink.text
    }

    public func close() async {
        try? await channel?.close(); try? await group.shutdownGracefully()
    }

    private func connected() throws -> Channel {
        guard let channel else { throw TestSupportError("connect(port:) was not called") }
        return channel
    }
}
