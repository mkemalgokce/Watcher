import Foundation
import WatcherCore
import WatcherUI

/// Runs an engine on whatever port the system gives, whatever port the app asks for, so a test never races for a port.
public final class AnyPortRunner: ProxyRunning, @unchecked Sendable {
    private let engine: WatcherEngine

    public init(_ engine: WatcherEngine) {
        self.engine = engine
    }

    public var isRunning: Bool {
        engine.isRunning
    }

    public var boundPort: Int? {
        engine.boundPort
    }

    public func start(port _: Int?) async throws -> Int {
        try await engine.start(port: 0)
    }

    public func stop() async throws {
        try await engine.stop()
    }
}
