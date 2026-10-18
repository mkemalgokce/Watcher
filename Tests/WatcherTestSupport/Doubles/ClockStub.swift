import Foundation

/// A clock that answers the given times in turn and then keeps answering the last one.
public final class ClockStub: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Date]

    public init(_ times: Date...) {
        self.times = times.isEmpty ? [Date(timeIntervalSince1970: 1_700_000_000)] : times
    }

    public var now: @Sendable () -> Date {
        { [self] in
            lock.withLock { times.count > 1 ? times.removeFirst() : times[0] }
        }
    }
}
