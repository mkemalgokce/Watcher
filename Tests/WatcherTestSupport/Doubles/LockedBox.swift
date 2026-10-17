import Foundation

/// A value that closures called from other threads can change and the test can read afterwards.
public final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    public init(_ value: Value) {
        storage = value
    }

    public var value: Value {
        lock.withLock { storage }
    }

    public func mutate(_ change: (inout Value) -> Void) {
        lock.withLock { change(&storage) }
    }
}

public extension LockedBox where Value == [[String]] {
    func mutate(_ arguments: [String]) {
        mutate { $0.append(arguments) }
    }
}
