import WatcherCore

/// The Mac's own web proxy setting. A protocol rather than `SystemProxy`'s `run` seam so controller tests can make it
/// fail and order its calls against the proxy runner's, and previews can use one that does nothing.
public protocol SystemProxying: Sendable {
    /// True when an earlier run turned the system proxy on and never put the original back.
    var hasPendingRestore: Bool { get }
    func enable(port: Int) throws
    func disable() throws
}

extension SystemProxy: SystemProxying {
    public func enable(port: Int) throws {
        try enable(host: "127.0.0.1", port: port)
    }
}

/// Previews: never touches the Mac's network settings.
struct InertSystemProxy: SystemProxying {
    var hasPendingRestore: Bool {
        false
    }

    func enable(port _: Int) {}
    func disable() {}
}
