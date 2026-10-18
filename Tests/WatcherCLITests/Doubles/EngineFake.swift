import Foundation
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

/// An engine that starts and stops without opening a socket. It records `start <port>` and `stop` into `log`,
/// which other doubles may share to check the order of calls, and answers MCP lines with `answer`.
final class EngineFake: EngineControlling, @unchecked Sendable {
    struct Failure: Error, Equatable {}

    let store = FlowStore()
    let breakpoints = BreakpointCenter()
    let settings: SettingsStore
    var onLog: @Sendable (String) -> Void = { _ in }
    var decryptsHTTPS = true

    private let log: LockedBox<[String]>
    private let boundPort: Int
    private let failsToStart: Bool
    private let answer: @Sendable (String) async -> String?
    private let decryptedAtStart = LockedBox<Bool?>(nil)

    init(
        settings: SettingsStore,
        boundPort: Int = 9123,
        failsToStart: Bool = false,
        log: LockedBox<[String]> = LockedBox([]),
        answer: (@Sendable (String) async -> String?)? = nil
    ) {
        self.settings = settings; self.boundPort = boundPort; self.failsToStart = failsToStart; self.log = log
        self.answer = answer ?? { "reply to \($0)" }
    }

    /// `start <requested port>` and `stop`, in order.
    var calls: [String] {
        log.value.filter { $0.hasPrefix("start") || $0 == "stop" }
    }

    /// Whether HTTPS was to be decrypted when the proxy started; nil before it did.
    var decryptedHTTPSAtStart: Bool? {
        decryptedAtStart.value
    }

    func start(port: Int?) async throws -> Int {
        log.mutate { $0.append("start \(port.map(String.init) ?? "any")") }
        decryptedAtStart.mutate { [decryptsHTTPS] in $0 = decryptsHTTPS }
        if failsToStart {
            throw Failure()
        }
        return boundPort
    }

    func stop() async throws {
        log.mutate { $0.append("stop") }
    }

    func mcpHandler() -> @Sendable (String) async -> String? {
        answer
    }
}
