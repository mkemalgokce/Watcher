import Foundation
import Observation
import WatcherCore

/// The window's mirror of the store: the captured flows, what the search, sidebar and sort leave visible, the sidebar
/// counts and the selection. Derived values are recomputed once per batch of changes, not on every view update.
@MainActor @Observable
final class FlowListViewModel {
    private(set) var flows: [Flow] = []
    var selection: Flow.ID?
    var query = FlowFilter() {
        didSet { refresh(ifChanged: oldValue, query) }
    }

    var sidebar = SidebarItem.all {
        didSet { refresh(ifChanged: oldValue, sidebar) }
    }

    /// Column the list is sorted by (click a header); arrival order by default, so live traffic appends at the bottom.
    var sortOrder = [KeyPathComparator(\Flow.sequence)] {
        didSet { refresh(ifChanged: oldValue, sortOrder) }
    }

    var hidesAppleTraffic = false {
        didSet { refresh(ifChanged: oldValue, hidesAppleTraffic) }
    }

    var hidesSystemServices = false {
        didSet { refresh(ifChanged: oldValue, hidesSystemServices) }
    }

    /// Whether the sidebar's System Services section is open; it starts closed, as daemons are rarely what is wanted.
    var expandsSystemServices = false

    private(set) var visibleFlows: [Flow] = []
    private(set) var counts = SidebarCounts()
    private(set) var visibleBytes = 0

    @ObservationIgnored private var indexByID: [Flow.ID: Int] = [:]
    @ObservationIgnored private var pendingEvents: [FlowEvent] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private let store: FlowStore
    @ObservationIgnored private let sleep: Sleep

    init(store: FlowStore, sleep: @escaping Sleep) {
        self.store = store
        self.sleep = sleep
    }

    var selectedFlow: Flow? {
        selection.flatMap { indexByID[$0] }.map { flows[$0] }
    }

    /// "12 requests", or "3 of 12 requests" while a filter hides some.
    var countText: String {
        visibleFlows.count == flows.count
            ? "\(flows.count) requests"
            : "\(visibleFlows.count) of \(flows.count) requests"
    }

    /// The search field and quick filters combined with the sidebar choice.
    var effectiveFilter: FlowFilter {
        var filter = query
        switch sidebar {
        case .all: break
        case .starred: filter.starredOnly = true
        case .errors: filter.errorsOnly = true
        case .webSocket: filter.webSocketOnly = true
        case let .app(name): filter.app = name
        case let .domain(name): filter.host = name
        }
        return filter
    }

    func clearFilters() {
        query.reset()
        sidebar = .all
    }

    func observeStore() {
        let events = store.events()
        Task { [weak self] in
            for await event in events {
                self?.enqueue(event)
            }
        }
    }

    /// Store events arrive one per request, header and chunk; applying each on its own re-rendered the whole window
    /// hundreds of times a second under load. They are collected and applied together a few times a second instead.
    func enqueue(_ event: FlowEvent) {
        pendingEvents.append(event)
        guard flushTask == nil else { return }
        let sleep = sleep
        flushTask = Task { [weak self] in
            try? await sleep(.milliseconds(80))
            self?.flushEvents()
        }
    }

    /// Applies every collected event with a single change to `flows`.
    func flushEvents() {
        flushTask?.cancel(); flushTask = nil
        let events = pendingEvents
        pendingEvents = []
        guard !events.isEmpty else { return }
        var batch = EventBatch(flows: flows, index: indexByID)
        events.forEach { batch.apply($0) }
        if !batch.removed.isEmpty {
            let doomed = Set(batch.removed.keys)
            batch.flows.removeAll { doomed.contains($0.id) }
            batch.index = Self.index(of: batch.flows)
        }
        flows = batch.flows
        indexByID = batch.index
        if batch.wasCleared || selection.map({ batch.index[$0] == nil }) == true {
            selection = nil
        }
        refreshDerived()
    }

    /// Takes everything currently in the store without waiting for its events (previews and snapshots).
    func syncFromStore() {
        pendingEvents = []
        flows = store.all
        indexByID = Self.index(of: flows)
        refreshDerived()
    }

    private static func index(of flows: [Flow]) -> [Flow.ID: Int] {
        Dictionary(uniqueKeysWithValues: flows.enumerated().map { ($1.id, $0) })
    }

    private func refresh<Value: Equatable>(ifChanged old: Value, _ new: Value) {
        if old != new {
            refreshDerived()
        }
    }

    /// The sidebar rows of one kind; the system services are gone while they are hidden.
    func groups(of kind: ClientKind) -> [FlowGroup] {
        kind == .service && hidesSystemServices ? [] : counts.apps.filter { $0.kind == kind }
    }

    private func isHidden(_ flow: Flow) -> Bool {
        (hidesAppleTraffic && AppleTraffic.isApple(flow.request.host))
            || (hidesSystemServices && flow.request.clientKind == .service)
    }

    private func refreshDerived() {
        let hidesAny = hidesAppleTraffic || hidesSystemServices
        let shown = hidesAny ? flows.filter { !isHidden($0) } : flows
        let filtered = effectiveFilter.apply(to: shown)
        // Arrival order is the order flows are kept in; sorting is only paid for when another column was chosen.
        visibleFlows = sortOrder == [KeyPathComparator(\Flow.sequence)] ? filtered : filtered.sorted(using: sortOrder)
        visibleBytes = visibleFlows.reduce(0) { $0 + ($1.response?.body.count ?? 0) }
        var next = SidebarCounts(apps: FlowGrouping.apps(flows), domains: FlowGrouping.domains(flows))
        for flow in flows {
            next.starred += flow.isStarred ? 1 : 0
            next.errors += FlowFilter.isError(flow) ? 1 : 0
            next.webSocket += flow.isWebSocket ? 1 : 0
        }
        if next != counts {
            counts = next
        }
    }
}

/// The flows and their positions while one batch of store events is applied.
private struct EventBatch {
    var flows: [Flow]
    var index: [Flow.ID: Int]
    /// Flows taken out in this batch, with the place each had, so one added again takes that place back.
    var removed: [Flow.ID: Int] = [:]
    var wasCleared = false

    mutating func apply(_ event: FlowEvent) {
        switch event {
        case let .added(flow):
            if let position = index[flow.id] ?? removed.removeValue(forKey: flow.id) {
                flows[position] = flow
                index[flow.id] = position
            } else {
                index[flow.id] = flows.count
                flows.append(flow)
            }
        case let .updated(flow):
            if let position = index[flow.id] {
                flows[position] = flow
            }
        case let .removed(id):
            if let position = index.removeValue(forKey: id) {
                removed[id] = position
            }
        case .cleared:
            flows = []; index = [:]; removed = [:]; wasCleared = true
        }
    }
}
