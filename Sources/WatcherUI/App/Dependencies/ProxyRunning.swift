import WatcherCore

/// Starting and stopping the proxy listener, and whether the traffic it carries is kept.
public protocol ProxyRunning: AnyObject, Sendable {
    var isRunning: Bool { get }
    /// While false, requests still pass through but none are listed or kept; a request already in flight still finishes.
    var isRecording: Bool { get set }
    var boundPort: Int? { get }
    /// Returns the port actually bound.
    func start(port: Int?) async throws -> Int
    func stop() async throws
}

extension WatcherEngine: ProxyRunning {}
