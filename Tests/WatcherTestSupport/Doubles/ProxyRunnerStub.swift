import Foundation
import WatcherUI

/// A proxy that starts and stops without opening a socket: it binds `boundPort`, or throws `failure` when set.
public final class ProxyRunnerStub: ProxyRunning, @unchecked Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public init() {}

        public var description: String {
            "address in use"
        }
    }

    private let lock = NSLock()
    private let log: LockedBox<[String]>
    private let port: Int
    private var running = false
    private var failure: (any Error)?
    private var runsDespiteFailure = false

    public init(boundPort: Int = 9123, log: LockedBox<[String]>? = nil) {
        port = boundPort
        self.log = log ?? LockedBox([])
    }

    /// `start <requested port>` and `stop`, in order.
    public var calls: [String] {
        log.value.filter { $0.hasPrefix("start") || $0 == "stop" }
    }

    /// With `stillRunning`, the failed start leaves the proxy listening, as a runner that bound a port and then threw.
    public func failStarting(_ failure: (any Error)? = Failure(), stillRunning: Bool = false) {
        lock.withLock { self.failure = failure; runsDespiteFailure = stillRunning }
    }

    public var isRunning: Bool {
        lock.withLock { running }
    }

    public var boundPort: Int? {
        lock.withLock { running ? port : nil }
    }

    public func start(port requested: Int?) async throws -> Int {
        log.mutate { $0.append("start \(requested.map(String.init) ?? "any")") }
        if let failure = lock.withLock({ failure }) {
            if runsDespiteFailure {
                lock.withLock { running = true }
            }
            throw failure
        }
        lock.withLock { running = true }
        return port
    }

    public func stop() async throws {
        log.mutate { $0.append("stop") }
        lock.withLock { running = false }
    }
}
