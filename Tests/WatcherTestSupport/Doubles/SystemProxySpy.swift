import Foundation
import WatcherUI

/// Stands in for the Mac's proxy settings: records `enable <port>` and `disable` calls, optionally into a log shared
/// with other doubles, and fails when told to.
public final class SystemProxySpy: SystemProxying, @unchecked Sendable {
    public struct Failure: Error {}

    private let lock = NSLock()
    private let log: LockedBox<[String]>
    private var failing = false
    private let pendingRestore: Bool

    public init(hasPendingRestore: Bool = false, log: LockedBox<[String]>? = nil) {
        pendingRestore = hasPendingRestore
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

    public func enable(port: Int) throws {
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
