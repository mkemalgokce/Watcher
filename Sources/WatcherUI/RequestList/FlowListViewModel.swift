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
        didSet {
            if hidesSystemServices, selectsAServiceRow {
                sidebar = .all
            }
            refresh(ifChanged: oldValue, hidesSystemServices)
        }
    }

    /// Hiding the services removes their rows; leaving one selected would filter the list down to nothing.
    private var selectsAServiceRow: Bool {
        guard case let .app(name) = sidebar else { return false }
        return counts.apps.contains { $0.name == name && $0.kind == .service }
    }

    /// Whether the sidebar's System Services section is open; it starts closed, as daemons are rarely what is wanted.
    var expandsSystemServices = false

    private static let arrivalOrder = [KeyPathComparator(\Flow.sequence)]
    private static let typingPause = Duration.milliseconds(200)

    private(set) var visibleFlows: [Flow] = []
    private(set) var counts = SidebarCounts()
    private(set) var visibleBytes = 0
    /// Longest duration among the visible rows; the Duration column draws its bars against it.
    private(set) var visibleSlowest: TimeInterval = 0

    @ObservationIgnored private var indexByID: [Flow.ID: Int] = [:]
    @ObservationIgnored private var pendingEvents: [FlowEvent] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var visibleTask: Task<Void, Never>?
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

    /// A change to what is shown leaves the sidebar counts alone: they count every flow, whatever is filtered.
    private func refresh<Value: Equatable>(ifChanged old: Value, _ new: Value) {
        if old != new {
            refreshVisible()
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
        refreshVisible()
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

    /// Cheap filters apply on the spot. Searching text through a long list (bodies especially) or sorting it takes long
    /// enough to freeze the window, so that runs off the main thread, after a pause in typing, and a newer change
    /// replaces it; until it lands the list keeps showing the previous result.
    private func refreshVisible() {
        visibleTask?.cancel(); visibleTask = nil
        let work = VisibleRows(
            flows: flows, filter: effectiveFilter, hidesApple: hidesAppleTraffic, hidesServices: hidesSystemServices,
            sort: sortOrder == Self.arrivalOrder ? nil : SendableSort(order: sortOrder)
        )
        guard work.isExpensive else { return show(work.run()) }
        let sleep = sleep
        visibleTask = Task { [weak self] in
            try? await sleep(Self.typingPause)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { work.run() }.value
            guard !Task.isCancelled else { return }
            self?.show(result)
        }
    }

    private func show(_ rows: VisibleRows.Result) {
        visibleFlows = rows.flows
        visibleBytes = rows.bytes
        visibleSlowest = rows.slowest
    }
}

/// What the list shows for a set of flows and filters; a value so it can be worked out on any thread.
private struct VisibleRows: Sendable {
    struct Result: Sendable {
        let flows: [Flow]
        let bytes: Int
        let slowest: TimeInterval
    }

    /// Below this many flows even a text search is quick enough to run in place.
    static let backgroundThreshold = 2000

    let flows: [Flow]
    let filter: FlowFilter
    let hidesApple: Bool
    let hidesServices: Bool
    /// nil keeps arrival order, which is how the flows are stored, so nothing is sorted.
    let sort: SendableSort?

    var isExpensive: Bool {
        flows.count >= Self.backgroundThreshold && (!filter.text.isEmpty || !filter.terms.isEmpty || sort != nil)
    }

    func run() -> Result {
        let shown = hidesApple || hidesServices ? flows.filter { !isHidden($0) } : flows
        let filtered = filter.apply(to: shown)
        let rows = sort.map { filtered.sorted(using: $0.order) } ?? filtered
        return Result(
            flows: rows, bytes: rows.reduce(0) { $0 + ($1.response?.body.count ?? 0) },
            slowest: rows.lazy.compactMap(\.duration).max() ?? 0
        )
    }

    private func isHidden(_ flow: Flow) -> Bool {
        let isApple = hidesApple && AppleTraffic.isApple(flow.request.host)
        return isApple || (hidesServices && flow.request.clientKind == .service)
    }
}

/// Key-path comparators are immutable, but not marked Sendable.
private struct SendableSort: @unchecked Sendable {
    let order: [KeyPathComparator<Flow>]
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
