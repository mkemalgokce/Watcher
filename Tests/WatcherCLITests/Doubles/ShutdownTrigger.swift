@testable import watcher_cli
import WatcherTestSupport

/// Stands in for Ctrl-C: `signal` is what the command waits on, `isAwaited` tells the test it has started listening,
/// and `fire` asks it to shut down.
final class ShutdownTrigger: @unchecked Sendable {
    private let continuation = LockedBox<AsyncStream<Void>.Continuation?>(nil)

    var isAwaited: Bool {
        continuation.value != nil
    }

    var signal: ShutdownSignal {
        { [continuation] in
            AsyncStream { new in continuation.mutate { $0 = new } }
        }
    }

    func fire() {
        continuation.value?.yield()
    }
}
