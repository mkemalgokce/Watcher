import Foundation
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

/// An engine that starts and stops without opening a socket. It records `start <port>`, `apply` and `stop` into `log`,
/// which other doubles may share to check the order of calls, and answers MCP lines with `answer`.
final class EngineFake: EngineControlling, @unchecked Sendable {
    struct Failure: Error, Equatable {}

    let store = FlowStore()
    let breakpoints = BreakpointCenter()
    let settings: SettingsStore
    var onLog: @Sendable (String) -> Void = { _ in }

    private let log: LockedBox<[String]>
    private let boundPort: Int
    private let failsToStart: Bool
    private let answer: @Sendable (String) async -> String?
    private let appliedSettings = LockedBox<[WatcherSettings]>([])

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

    /// `start <requested port>`, `apply` and `stop`, in order.
    var calls: [String] {
        log.value.filter { $0.hasPrefix("start") || $0 == "apply" || $0 == "stop" }
    }

    var applied: [WatcherSettings] {
        appliedSettings.value
    }

    func start(port: Int?) async throws -> Int {
        log.mutate { $0.append("start \(port.map(String.init) ?? "any")") }
        if failsToStart {
            throw Failure()
        }
        return boundPort
    }

    func stop() async throws {
        log.mutate { $0.append("stop") }
    }

    func apply(_ settings: WatcherSettings) async {
        log.mutate { $0.append("apply") }
        appliedSettings.mutate { $0.append(settings) }
    }

    func mcpHandler() -> @Sendable (String) async -> String? {
        answer
    }
}
