import Foundation

/// Set from Observation's onChange, which may run on another thread.
public final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    public init() {}

    public var value: Bool {
        lock.withLock { isSet }
    }

    public func set() {
        lock.withLock { isSet = true }
    }
}
