import Foundation

public enum FlowEvent: Sendable {
    case added(Flow)
    case updated(Flow)
    case removed(UUID)
    case cleared
}

/// Thread-safe in-memory session. The UI and CLI observe it through `events`.
public final class FlowStore: @unchecked Sendable {
    private let lock = NSLock()
    private var flows: [UUID: Flow] = [:]
    private var order: [UUID] = []
    private var counter = 0
    private var _isRecording = true
    private var _maxFlows = 0
    private var observers: [Int: AsyncStream<FlowEvent>.Continuation] = [:]
    private var nextObserver = 0
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(now: @escaping @Sendable () -> Date = Date.init, makeID: @escaping @Sendable () -> UUID = UUID.init) {
        self.now = now; self.makeID = makeID
    }

    /// While paused, requests still go through the proxy but are neither listed nor kept.
    public var isRecording: Bool {
        get { lock.withLock { _isRecording } }
        set { lock.withLock { _isRecording = newValue } }
    }

    /// Oldest requests are dropped beyond this many; 0 keeps everything.
    public var maxFlows: Int {
        get { lock.withLock { _maxFlows } }
        set { lock.withLock { _maxFlows = max(0, newValue) } }
    }

    public var all: [Flow] {
        lock.withLock { order.compactMap { flows[$0] } }
    }

    public func events() -> AsyncStream<FlowEvent> {
        AsyncStream { continuation in
            let token = lock.withLock {
                nextObserver += 1
                observers[nextObserver] = continuation
                return nextObserver
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.observers.removeValue(forKey: token) }
            }
        }
    }

    /// Returns the new flow; when recording is paused it is returned but not stored, so later updates to it are no-ops.
    func begin(_ request: RequestRecord) -> Flow {
        lock.withLock {
            counter += 1
            let flow = Flow(sequence: counter, request: request, id: makeID(), startedAt: now())
            guard _isRecording else { return flow }
            flows[flow.id] = flow; order.append(flow.id)
            trimLocked().forEach { publishLocked(.removed($0)) }
            publishLocked(.added(flow))
            return flow
        }
    }

    func update(_ id: UUID, _ change: (inout Flow) -> Void) {
        lock.withLock {
            guard var flow = flows[id] else { return }
            change(&flow); flows[id] = flow
            publishLocked(.updated(flow))
        }
    }

    /// shortcut: keeps only the newest messages per socket so a chatty connection cannot grow the session without bound.
    static let maxWebSocketMessages = 2000

    func appendWebSocketMessage(_ message: WebSocketMessage, to id: UUID) {
        update(id) {
            $0.webSocketMessages.append(message)
            if $0.webSocketMessages.count > Self.maxWebSocketMessages {
                $0.webSocketMessages.removeFirst($0.webSocketMessages.count - Self.maxWebSocketMessages)
            }
        }
    }

    /// Star or comment a flow; the change is published like any other update.
    public func annotate(_ id: UUID, starred: Bool? = nil, comment: String?? = nil) {
        update(id) { flow in
            if let starred {
                flow.isStarred = starred
            }
            if let comment {
                flow.comment = comment?.isEmpty == true ? nil : comment
            }
        }
    }

    /// Drops a flow, e.g. a request the Block List hides or one the user deleted.
    public func discard(_ id: UUID) {
        discard([id])
    }

    /// One pass over the order for any number of flows; removing them one by one was quadratic for a large selection.
    public func discard(_ ids: Set<UUID>) {
        lock.withLock {
            ids.forEach { flows.removeValue(forKey: $0) }; order.removeAll { ids.contains($0) }
            ids.forEach { publishLocked(.removed($0)) }
        }
    }

    /// Replaces the session with imported flows, renumbering them, in one step so no live request lands in between.
    public func load(_ imported: [Flow]) {
        lock.withLock { replaceLocked(with: imported) }
    }

    /// Returns what was removed, in list order, so the caller can offer Undo.
    @discardableResult
    public func clear() -> [Flow] {
        lock.withLock {
            let removed = order.compactMap { flows[$0] }
            flows.removeAll(); order.removeAll(); counter = 0; publishLocked(.cleared)
            return removed
        }
    }

    /// Undoes a clear: puts `cleared` back before the requests that arrived since, renumbering all, in one step so none are lost.
    public func restore(_ cleared: [Flow]) {
        lock.withLock {
            let returning = cleared.filter { flows[$0.id] == nil }
            guard !returning.isEmpty else { return }
            replaceLocked(with: returning + order.compactMap { flows[$0] })
        }
    }

    /// Makes `replacement` the whole session, renumbered and trimmed, and tells observers; call with the lock held.
    private func replaceLocked(with replacement: [Flow]) {
        flows.removeAll(); order.removeAll(); counter = 0
        for var flow in replacement {
            counter += 1; flow.sequence = counter
            flows[flow.id] = flow; order.append(flow.id)
        }
        trimLocked()
        publishLocked(.cleared)
        order.compactMap { flows[$0] }.forEach { publishLocked(.added($0)) }
    }

    /// Drops the oldest flows beyond `maxFlows`; call with the lock held.
    @discardableResult
    private func trimLocked() -> [UUID] {
        var dropped: [UUID] = []
        while _maxFlows > 0, order.count > _maxFlows {
            let oldest = order.removeFirst(); flows.removeValue(forKey: oldest); dropped.append(oldest)
        }
        return dropped
    }

    /// Call with the lock held so observers see events in the order the changes were applied; yield neither blocks nor runs onTermination inline.
    private func publishLocked(_ event: FlowEvent) {
        observers.values.forEach { $0.yield(event) }
    }
}
