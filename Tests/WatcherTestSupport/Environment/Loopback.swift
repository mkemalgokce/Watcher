import NIO

/// Whether something is listening, asked by connecting.
public enum Loopback {
    public static func accepts(host: String = "127.0.0.1", port: Int, timeout: TimeAmount = .seconds(2)) async -> Bool {
        let channel = try? await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connectTimeout(timeout)
            .connect(host: host, port: port).get()
        try? await channel?.close()
        return channel != nil
    }
}
