import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Past a couple of thousand requests, searching text or sorting no longer runs on the main thread.
@MainActor
@Suite(.tags(.unit))
struct FlowListViewModelLargeListTests {
    private let count = 2500

    private func loaded(sleep: Sleep? = nil) -> FlowListViewModel {
        let list = FlowListViewModel(store: FlowStore(), sleep: sleep ?? sleepUntilCancelled)
        (1 ... count).forEach { list.enqueue(.added(.fixture(sequence: $0, status: $0 % 10 == 0 ? 500 : 200))) }
        list.flushEvents()
        return list
    }

    @Test
    func aCheapFilterOnALargeListAppliesAtOnce() {
        let list = loaded()
        list.query.errorsOnly = true
        #expect(list.visibleFlows.count == count / 10)
    }

    @Test
    func clearingFiltersOnALargeListAppliesAtOnce() async {
        let gate = SleepGate()
        let list = loaded(sleep: gate.sleep)
        list.query.text = "/7"
        #expect(await eventually { gate.durations.contains(.milliseconds(200)) })
        list.clearFilters()
        #expect(list.visibleFlows.count == count, "no pause and no stale rows when the search is gone")
    }

    @Test
    func aTextSearchOnALargeListLandsAfterAPause() async {
        let gate = SleepGate()
        let list = loaded(sleep: gate.sleep)
        list.query.text = "/2499"
        #expect(list.visibleFlows.count == count, "the previous rows stay until the search has run")
        #expect(await eventually { gate.durations.contains(.milliseconds(200)) })
        gate.releaseAll()
        #expect(await eventually { list.visibleFlows.map(\.sequence) == [2499] })
    }

    @Test
    func aNewerSearchReplacesOneStillWaiting() async {
        let gate = SleepGate()
        let list = loaded(sleep: gate.sleep)
        list.query.text = "/1"
        list.query.text = "/2499"
        #expect(await eventually { gate.durations.contains(.milliseconds(200)) })
        gate.releaseAll()
        #expect(await eventually { list.visibleFlows.map(\.sequence) == [2499] })
    }

    @Test
    func theSidebarCountsDoNotChangeWithTheFilter() {
        let list = loaded()
        let before = list.counts
        list.query.text = "/2499"
        #expect(list.counts == before)
    }

    @Test
    func aSmallListSearchesOnTheSpot() {
        let list = FlowListViewModel(store: FlowStore(), sleep: sleepUntilCancelled)
        (1 ... 20).forEach { list.enqueue(.added(.fixture(sequence: $0, status: 200))) }
        list.flushEvents()
        list.query.text = "/7"
        #expect(list.visibleFlows.map(\.sequence) == [7])
    }

    @Test
    func theSlowestVisibleRequestFollowsTheFilter() {
        let list = FlowListViewModel(store: FlowStore(), sleep: sleepUntilCancelled)
        list.enqueue(.added(.fixture(sequence: 1, request: .fixture(path: "/fast"), duration: 0.1)))
        list.enqueue(.added(.fixture(sequence: 2, request: .fixture(path: "/slow"), duration: 3)))
        list.flushEvents()
        #expect(list.visibleSlowest == 3)
        list.query.text = "/fast"
        #expect(list.visibleSlowest == 0.1)
    }
}
