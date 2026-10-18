import Foundation
import WatcherCore

/// A `Sleep` that waits until the test lets it go, so code after a delay runs exactly when the test says.
public final class SleepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var recorded: [Duration] = []
    private var returned = 0

    public init() {}

    public var durations: [Duration] {
        lock.withLock { recorded }
    }

    public var waitingCount: Int {
        lock.withLock { waiting.count }
    }

    /// Waits that were let go and have handed control back to their caller.
    public var returnedCount: Int {
        lock.withLock { returned }
    }

    public var sleep: Sleep {
        { [self] duration in
            await withCheckedContinuation { continuation in
                lock.withLock {
                    recorded.append(duration)
                    waiting.append(continuation)
                }
            }
            lock.withLock { returned += 1 }
        }
    }

    /// Ends the oldest wait still running.
    public func releaseOldest() {
        let next: CheckedContinuation<Void, Never>? = lock.withLock { waiting.isEmpty ? nil : waiting.removeFirst() }
        next?.resume()
    }

    public func releaseAll() {
        let all = lock.withLock {
            defer { waiting = [] }
            return waiting
        }
        all.forEach { $0.resume() }
    }
}
