import Foundation
import WatcherUI

/// Stands in for the Mac's proxy settings: records `enable <port>` and `disable` calls, optionally into a log shared
/// with other doubles, and fails when told to.
public final class SystemProxySpy: SystemProxying, @unchecked Sendable {
    public struct Failure: Error {}

    private let lock = NSLock()
    private let log: LockedBox<[String]>
    private var failing = false
    private var enableStarted = 0
    private let pendingRestore: Bool
    private let enableGate: DispatchSemaphore?

    /// With `enableGate`, `enable` waits for the test to signal it, so a switch can be held half way.
    public init(
        hasPendingRestore: Bool = false, log: LockedBox<[String]>? = nil, enableGate: DispatchSemaphore? = nil
    ) {
        pendingRestore = hasPendingRestore
        self.enableGate = enableGate
        self.log = log ?? LockedBox([])
    }

    public var calls: [String] {
        log.value.filter { $0.hasPrefix("enable") || $0 == "disable" }
    }

    public var hasPendingRestore: Bool {
        pendingRestore
    }

    public func failFromNowOn() {
        lock.withLock { failing = true }
    }

    /// How many `enable` calls have started, including one still held by the gate.
    public var enableCallsStarted: Int {
        lock.withLock { enableStarted }
    }

    public func enable(port: Int) throws {
        lock.withLock { enableStarted += 1 }
        if let enableGate {
            _ = enableGate.wait(timeout: .now() + 5)
        }
        try record("enable \(port)")
    }

    public func disable() throws {
        try record("disable")
    }

    private func record(_ call: String) throws {
        if lock.withLock({ failing }) {
            throw Failure()
        }
        log.mutate { $0.append(call) }
    }
}
