import Foundation

/// Stands in for `networksetup`: records each call and whether it ran on the main thread, and answers like a Mac with
/// one service, Wi-Fi, whose proxies are off.
public final class NetworkSetupSpy: @unchecked Sendable {
    private let delay: TimeInterval
    private let lock = NSLock()
    private var calls: [(arguments: [String], onMain: Bool)] = []

    /// A real write takes about 0.1 s; pass that as `delay` to check a caller does not wait for it.
    public init(delay: TimeInterval = 0) {
        self.delay = delay
    }

    public var arguments: [[String]] {
        lock.withLock { calls.map(\.arguments) }
    }

    public var anyOnMain: Bool {
        lock.withLock { calls.contains { $0.onMain } }
    }

    public func run(_ arguments: [String]) -> String {
        lock.withLock { calls.append((arguments, Thread.isMainThread)) }
        Thread.sleep(forTimeInterval: delay)
        switch arguments.first {
        case "-listallnetworkservices": return "An asterisk (*) denotes a disabled service.\nWi-Fi\n"
        case "-getwebproxy", "-getsecurewebproxy": return "Enabled: No\nServer: \nPort: 0\n"
        default: return ""
        }
    }
}
