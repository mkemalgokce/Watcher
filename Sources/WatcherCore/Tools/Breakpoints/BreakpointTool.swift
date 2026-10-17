import Foundation

/// Holds matching requests/responses until a person resolves them in the UI or CLI.
public final class BreakpointCenter: @unchecked Sendable {
    public enum Phase: String, Sendable { case request, response }

    public struct Hit: Identifiable, Sendable {
        public let id = UUID()
        public let phase: Phase
        public var request: RequestRecord
        public var response: ResponseRecord?
        /// When it was paused; clients give up after their own timeout (often 30–60 s), so the UI shows how long it has waited.
        public let pausedAt = Date()

        public init(phase: Phase, request: RequestRecord, response: ResponseRecord? = nil) {
            self.phase = phase; self.request = request; self.response = response
        }
    }

    public enum Resolution: Sendable {
        /// Continue with the (possibly edited) message.
        case proceed(request: RequestRecord, response: ResponseRecord?)
        case abort
    }

    private let lock = NSLock()
    private var hits: [Hit] = []
    private var waiting: [UUID: CheckedContinuation<Resolution, Never>] = [:]
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init() {}

    public var pending: [Hit] {
        lock.withLock { hits }
    }

    public func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let token = UUID()
            lock.withLock { observers[token] = continuation }
            continuation.onTermination = { [weak self] _ in self?.lock.withLock { _ = self?.observers.removeValue(forKey: token) } }
        }
    }

    func hold(phase: Phase, request: RequestRecord, response: ResponseRecord? = nil) async -> Resolution {
        let hit = Hit(phase: phase, request: request, response: response)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Resolution, Never>) in
            lock.withLock { hits.append(hit); waiting[hit.id] = continuation }
            notify()
        }
    }

    public func resolve(_ id: UUID, with resolution: Resolution) {
        let continuation: CheckedContinuation<Resolution, Never>? = lock.withLock {
            hits.removeAll { $0.id == id }
            return waiting.removeValue(forKey: id)
        }
        continuation?.resume(returning: resolution)
        notify()
    }

    /// Drops every held message (the client gets a 502).
    public func abortAll() {
        for hit in pending {
            resolve(hit.id, with: .abort)
        }
    }

    /// Lets everything through unchanged, e.g. when the tool is switched off or the proxy stops.
    public func releaseAll() {
        for hit in pending {
            resolve(hit.id, with: .proceed(request: hit.request, response: hit.response))
        }
    }

    private func notify() {
        let targets = lock.withLock { Array(observers.values) }
        targets.forEach { $0.yield() }
    }
}

struct BreakpointTool: Tool {
    let name = "Breakpoint"
    var needsRequestBody: Bool {
        entries.contains { $0.rule.onRequest || $0.matcher.readsBody }
    }

    var inspectsResponses: Bool {
        entries.contains { $0.rule.onResponse }
    }

    private let entries: [(rule: BreakpointRule, matcher: RequestMatcher)]
    private let center: BreakpointCenter

    init(rules: [BreakpointRule], center: BreakpointCenter) {
        entries = rules.map { ($0, $0.matching.compile()) }
        self.center = center
    }

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        guard entries.contains(where: { $0.rule.onRequest && $0.matcher.matches(request) }) else { return .forward }
        switch await center.hold(phase: .request, request: request) {
        case let .proceed(edited, _): request = edited; return .forward
        case .abort: return .respond(ProxyServer.message(502, "Request aborted at a Watcher breakpoint"))
        }
    }

    func intercept(response: inout ResponseRecord, for request: RequestRecord) async {
        guard entries.contains(where: { $0.rule.onResponse && $0.matcher.matches(request) }) else { return }
        switch await center.hold(phase: .response, request: request, response: response) {
        case let .proceed(_, edited): if let edited {
                response = edited
            }
        case .abort: response = ProxyServer.message(502, "Response aborted at a Watcher breakpoint")
        }
    }
}
