@testable import WatcherUI

/// Keeps the handler the app would run on quit, so a test can quit on demand.
@MainActor
public final class AppLifecycleSpy {
    private var handlers: [@MainActor () -> Void] = []

    public init() {}

    public var onTerminate: OnTerminate {
        { [self] handler in handlers.append(handler) }
    }

    public func terminate() {
        handlers.forEach { $0() }
    }
}
