import Foundation

/// Holds matching requests/responses until a person resolves them in the UI or CLI.
public final class BreakpointCenter: @unchecked Sendable {
    public enum Phase: String, Sendable { case request, response }

    public struct Hit: Identifiable, Sendable {
        public let id: UUID
        public let phase: Phase
        public var request: RequestRecord
        public var response: ResponseRecord?
        /// When it was paused; clients give up after their own timeout (often 30–60 s), so the UI shows how long it has waited.
        public let pausedAt: Date

        public init(
            id: UUID = UUID(),
            phase: Phase,
            request: RequestRecord,
            response: ResponseRecord? = nil,
            pausedAt: Date = Date()
        ) {
            self.id = id; self.phase = phase; self.request = request; self.response = response; self.pausedAt = pausedAt
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

    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(now: @escaping @Sendable () -> Date = { Date() }, makeID: @escaping @Sendable () -> UUID = { UUID() }) {
        self.now = now; self.makeID = makeID
    }

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
        let hit = Hit(id: makeID(), phase: phase, request: request, response: response, pausedAt: now())
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
