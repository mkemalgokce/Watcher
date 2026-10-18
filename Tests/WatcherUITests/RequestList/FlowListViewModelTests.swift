import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// How store events become what the list, sidebar and status bar show.
@MainActor
@Suite(.tags(.unit))
struct FlowListViewModelTests {
    private static let tenBytes = Data(repeating: 0, count: 10)
    private let store = FlowStore()

    private func list(sleep: Sleep? = nil) -> FlowListViewModel {
        FlowListViewModel(store: store, sleep: sleep ?? sleepUntilCancelled)
    }

    @Test
    func eventsAreAppliedTogetherInOrder() {
        let list = list()
        let flows = (1 ... 500).map { Flow.fixture(sequence: $0, status: 200) }
        flows.forEach { list.enqueue(.added($0)) }
        #expect(list.flows.isEmpty, "nothing changes until the batch is flushed")
        list.flushEvents()
        #expect(list.flows.map(\.sequence) == Array(1 ... 500))
        #expect(list.visibleFlows.count == 500)
    }

    @Test
    func aBatchIsFlushedAfterAShortPause() async {
        let gate = SleepGate()
        let list = list(sleep: gate.sleep)
        list.enqueue(.added(.fixture(sequence: 1, status: 200)))
        list.enqueue(.added(.fixture(sequence: 2, status: 200)))
        #expect(await eventually { gate.waitingCount == 1 }, "one timer for the whole batch")
        #expect(gate.durations == [.milliseconds(80)])
        #expect(list.flows.isEmpty)
        gate.releaseAll()
        #expect(await eventually { list.flows.count == 2 })
    }

    @Test
    func updatesRemovalsAndClearInOneBatch() {
        let list = list()
        let updated = Flow.fixture(sequence: 1, status: 200)
        let removed = Flow.fixture(sequence: 2, status: 200)
        let kept = Flow.fixture(sequence: 3, status: 200)
        [updated, removed, kept].forEach { list.enqueue(.added($0)) }
        list.flushEvents()
        list.selection = removed.id

        var changed = updated; changed.comment = "edited"
        list.enqueue(.updated(changed))
        list.enqueue(.removed(removed.id))
        list.enqueue(.added(.fixture(sequence: 4, status: 200)))
        list.flushEvents()
        #expect(list.flows.map(\.sequence) == [1, 3, 4])
        #expect(list.flows.first?.comment == "edited")
        #expect(list.selection == nil, "a removed flow cannot stay selected")
        #expect(list.selectedFlow == nil)

        list.selection = kept.id
        #expect(list.selectedFlow?.id == kept.id, "the index is rebuilt after a removal")

        list.enqueue(.cleared)
        list.enqueue(.added(.fixture(sequence: 9, status: 200)))
        list.flushEvents()
        #expect(list.flows.map(\.sequence) == [9])
        #expect(list.selection == nil)
    }

    @Test
    func anAddedFlowThatIsAlreadyListedReplacesIt() {
        let list = list()
        var flow = Flow.fixture(sequence: 1, status: 200)
        list.enqueue(.added(flow))
        flow.comment = "again"
        list.enqueue(.added(flow))
        list.flushEvents()
        #expect(list.flows.map(\.comment) == ["again"])
    }

    @Test
    func updateForUnknownFlowIsIgnored() {
        let list = list()
        list.enqueue(.updated(.fixture(sequence: 1, status: 200)))
        list.enqueue(.removed(UUID()))
        list.flushEvents()
        #expect(list.flows.isEmpty)
    }

    @Test
    func flushingWithNothingPendingChangesNothing() {
        let list = list()
        list.enqueue(.added(.fixture(sequence: 1, status: 200)))
        list.flushEvents()
        list.selection = list.flows[0].id
        list.flushEvents()
        #expect(list.flows.count == 1)
        #expect(list.selection != nil)
    }

    /// Integration with a real store: its events reach the list only through the flush timer.
    @Test
    func followsTheStoreThroughTheFlushTimer() async {
        let gate = SleepGate()
        let list = FlowListViewModel(store: store, sleep: gate.sleep)
        list.observeStore()
        store.load((1 ... 3).map { Flow.fixture(sequence: $0, status: 200) })
        #expect(await eventually { gate.waitingCount == 1 })
        #expect(list.flows.isEmpty, "nothing is applied before the timer ends")
        #expect(await eventually { gate.releaseAll(); return list.flows.count == 3 })

        let removed = list.flows[0].id
        store.discard([removed])
        #expect(await eventually { gate.releaseAll(); return list.flows.count == 2 })
        #expect(!list.flows.contains { $0.id == removed })
        #expect(gate.durations.allSatisfy { $0 == .milliseconds(80) })
    }

    @Test
    func aLargeBatchIsAppliedInOneFlush() {
        let list = list()
        let flows = (1 ... 2000).map { Flow.fixture(sequence: $0, status: 200) }
        flows.forEach { list.enqueue(.added($0)) }
        list.flushEvents()
        #expect(list.flows.count == 2000)
        #expect(list.flows.last?.sequence == 2000)

        let ids = Set(flows.prefix(1000).map(\.id))
        ids.forEach { list.enqueue(.removed($0)) }
        list.flushEvents()
        #expect(list.flows.count == 1000)
        #expect(list.flows.allSatisfy { !ids.contains($0.id) })
    }

    @Test
    func syncTakesWhatTheStoreHoldsWithoutWaiting() {
        store.load([.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 200)])
        let list = list()
        list.enqueue(.cleared)
        list.syncFromStore()
        #expect(list.flows.count == 2)
        list.flushEvents()
        #expect(list.flows.count == 2, "events taken before the sync are dropped")
    }

    @Test
    func sidebarAndQueryFilterTheList() {
        let list = list()
        [
            Flow.fixture(sequence: 1, status: 200, body: Self.tenBytes, clientApp: "Safari", starred: true),
            .fixture(sequence: 2, status: 500, body: Self.tenBytes, clientApp: "curl"),
            .fixture(sequence: 3, host: "cdn.other.org", status: nil),
            .fixture(sequence: 4, status: 101, body: Self.tenBytes),
        ].forEach { list.enqueue(.added($0)) }
        list.flushEvents()

        #expect(list.counts.starred == 1)
        #expect(list.counts.errors == 2)
        #expect(list.counts.webSocket == 1)
        #expect(Set(list.counts.apps.map(\.name)) == ["Safari", "curl"])
        #expect(Set(list.counts.domains.map(\.name)) == ["example.com", "other.org"])

        list.sidebar = .errors
        #expect(list.visibleFlows.map(\.sequence) == [2, 3])
        list.sidebar = .domain("other.org")
        #expect(list.visibleFlows.map(\.sequence) == [3])
        list.sidebar = .all
        list.query.text = "/4"
        #expect(list.visibleFlows.map(\.sequence) == [4])
        #expect(list.visibleBytes == 10)
        list.query.reset()
        #expect(list.visibleFlows.count == 4)
    }

    @Test(arguments: [
        (SidebarItem.all, [1, 2, 3]),
        (.starred, [1]),
        (.errors, [2]),
        (.webSocket, [3]),
        (.app("Safari"), [1]),
        (.domain("other.org"), [2]),
    ])
    func eachSidebarItemNarrowsTheList(item: SidebarItem, expected: [Int]) {
        let list = list()
        [
            Flow.fixture(sequence: 1, status: 200, clientApp: "Safari", starred: true),
            .fixture(sequence: 2, host: "api.other.org", status: 503),
            .fixture(sequence: 3, status: 101),
        ].forEach { list.enqueue(.added($0)) }
        list.flushEvents()
        list.sidebar = item
        #expect(list.visibleFlows.map(\.sequence) == expected)
    }

    @Test
    func sortingByAnyColumnAndBackToArrivalOrder() {
        let list = list()
        var slow = Flow.fixture(sequence: 1, status: 500); slow.duration = 3
        var fast = Flow.fixture(sequence: 2, host: "a.example.com", status: 200); fast.duration = 0.1
        var pending = Flow.fixture(sequence: 3, status: nil); pending.duration = nil; pending.state = .pending
        var failed = Flow.fixture(sequence: 4, status: nil); failed.duration = 1
        [slow, fast, pending, failed].forEach { list.enqueue(.added($0)) }
        list.flushEvents()
        #expect(list.visibleFlows.map(\.sequence) == [1, 2, 3, 4], "arrival order by default")

        list.sortOrder = [KeyPathComparator(\Flow.sortDuration)]
        #expect(list.visibleFlows.map(\.sequence) == [2, 4, 1, 3], "unfinished requests sort as the longest")
        list.sortOrder = [KeyPathComparator(\Flow.sortStatus, order: .reverse)]
        #expect(list.visibleFlows.first?.sequence == 1, "500 first when descending")
        #expect(list.visibleFlows.last?.sequence == 4, "a failure without a response sorts below everything")
        list.sortOrder = [KeyPathComparator(\Flow.sortURL)]
        #expect(list.visibleFlows.first?.request.host == "a.example.com")

        list.query.statusClasses = [2, 5]
        list.sortOrder = [KeyPathComparator(\Flow.sortDuration, order: .reverse)]
        #expect(list.visibleFlows.map(\.sequence) == [1, 2])
        var medium = Flow.fixture(sequence: 5, status: 201); medium.duration = 1
        list.enqueue(.added(medium)); list.flushEvents()
        #expect(list.visibleFlows.map(\.sequence) == [1, 5, 2])

        list.sortOrder = [KeyPathComparator(\Flow.sequence)]
        #expect(list.visibleFlows.map(\.sequence) == [1, 2, 5])
    }

    @Test
    func hidingAppleTrafficRefreshesTheList() {
        let list = list()
        [Flow.fixture(sequence: 1, host: "gateway.icloud.com", status: 200), .fixture(sequence: 2, status: 200)]
            .forEach { list.enqueue(.added($0)) }
        list.flushEvents()
        #expect(list.visibleFlows.count == 2)
        list.hidesAppleTraffic = true
        #expect(list.visibleFlows.map(\.sequence) == [2])
    }

    @Test
    func clearingFiltersShowsEverythingAgain() {
        let list = list()
        list.query.text = "/1"
        list.sidebar = .errors
        list.clearFilters()
        #expect(list.query == FlowFilter())
        #expect(list.sidebar == .all)
    }

    @Test
    func theCountSaysHowManyAreShownOfAll() {
        let list = list()
        let flows = [Flow.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 500)]
        flows.forEach { list.enqueue(.added($0)) }
        list.flushEvents()
        #expect(list.countText == "2 requests")
        list.sidebar = .errors
        #expect(list.countText == "1 of 2 requests")
    }
}
