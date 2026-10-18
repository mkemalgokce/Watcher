import Foundation
import WatcherCore

/// Records every requested wait and returns at once, so delays can be checked without spending them.
public final class SleepSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []

    public init() {}

    public var durations: [Duration] {
        lock.withLock { recorded }
    }

    public var sleep: Sleep {
        { [self] duration in lock.withLock { recorded.append(duration) } }
    }
}
