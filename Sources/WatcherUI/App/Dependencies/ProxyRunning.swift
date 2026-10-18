import WatcherCore

/// Starting and stopping the proxy listener.
public protocol ProxyRunning: AnyObject, Sendable {
    var isRunning: Bool { get }
    var boundPort: Int? { get }
    /// Returns the port actually bound.
    func start(port: Int?) async throws -> Int
    func stop() async throws
}

extension WatcherEngine: ProxyRunning {}
