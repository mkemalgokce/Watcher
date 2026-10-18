import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// How the window's model turns store events into what the list, sidebar and status bar show.
@MainActor
@Suite(.serialized, .tags(.unit))
struct AppModelTests {
    private static let tenBytes = Data(repeating: 0, count: 10)

    @Test
    func eventsAreAppliedTogetherInOrder() {
        let model = AppModel(listening: false)
        let flows = (1 ... 500).map { Flow.fixture(sequence: $0, status: 200) }
        flows.forEach { model.enqueue(.added($0)) }
        #expect(model.flows.isEmpty, "nothing changes until the batch is flushed")
        model.flushEvents()
        #expect(model.flows.map(\.sequence) == Array(1 ... 500))
        #expect(model.visibleFlows.count == 500)
    }

    @Test
    func updatesRemovalsAndClearInOneBatch() {
        let model = AppModel(listening: false)
        let updated = Flow.fixture(sequence: 1, status: 200)
        let removed = Flow.fixture(sequence: 2, status: 200)
        let kept = Flow.fixture(sequence: 3, status: 200)
        [updated, removed, kept].forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        model.selection = removed.id

        var changed = updated; changed.comment = "edited"
        model.enqueue(.updated(changed))
        model.enqueue(.removed(removed.id))
        model.enqueue(.added(.fixture(sequence: 4, status: 200)))
        model.flushEvents()
        #expect(model.flows.map(\.sequence) == [1, 3, 4])
        #expect(model.flows.first?.comment == "edited")
        #expect(model.selection == nil, "a removed flow cannot stay selected")
        #expect(model.selectedFlow == nil)

        model.selection = kept.id
        #expect(model.selectedFlow?.id == kept.id, "the index is rebuilt after a removal")

        model.enqueue(.cleared)
        model.enqueue(.added(.fixture(sequence: 9, status: 200)))
        model.flushEvents()
        #expect(model.flows.map(\.sequence) == [9])
        #expect(model.selection == nil)
    }

    @Test
    func updateForUnknownFlowIsIgnored() {
        let model = AppModel(listening: false)
        model.enqueue(.updated(.fixture(sequence: 1, status: 200)))
        model.enqueue(.removed(UUID()))
        model.flushEvents()
        #expect(model.flows.isEmpty)
    }

    /// Integration: the model follows a real store, and a burst of traffic reaches it as a batch, not one re-render
    /// per event.
    @Test(.tags(.timing))
    func followsStoreInBatches() async {
        let model = AppModel(listening: false)
        model.observeEngine()
        model.engine.store.load((1 ... 2000).map { Flow.fixture(sequence: $0, status: 200) })
        #expect(await eventually { model.flows.count == 2000 })
        #expect(model.flows.last?.sequence == 2000)

        let started = Date()
        let ids = Set(model.flows.prefix(1000).map(\.id))
        model.delete(ids)
        #expect(await eventually { model.flows.count == 1000 })
        #expect(Date().timeIntervalSince(started) < 2, "deleting a large selection must not be quadratic")
        #expect(model.flows.allSatisfy { !ids.contains($0.id) })
    }

    @Test
    func sidebarAndQueryFilterTheList() {
        let model = AppModel(listening: false)
        [
            Flow.fixture(sequence: 1, status: 200, body: Self.tenBytes, clientApp: "Safari", starred: true),
            .fixture(sequence: 2, status: 500, body: Self.tenBytes, clientApp: "curl"),
            .fixture(sequence: 3, host: "cdn.other.org", status: nil),
            .fixture(sequence: 4, status: 101, body: Self.tenBytes),
        ].forEach { model.enqueue(.added($0)) }
        model.flushEvents()

        #expect(model.counts.starred == 1)
        #expect(model.counts.errors == 2)
        #expect(model.counts.webSocket == 1)
        #expect(Set(model.counts.apps.map(\.name)) == ["Safari", "curl"])
        #expect(Set(model.counts.domains.map(\.name)) == ["example.com", "other.org"])

        model.sidebar = .errors
        #expect(model.visibleFlows.map(\.sequence) == [2, 3])
        model.sidebar = .domain("other.org")
        #expect(model.visibleFlows.map(\.sequence) == [3])
        model.sidebar = .all
        model.query.text = "/4"
        #expect(model.visibleFlows.map(\.sequence) == [4])
        #expect(model.visibleBytes == 10)
        model.query.reset()
        #expect(model.visibleFlows.count == 4)
    }

    @Test
    func sortingByAnyColumnAndBackToArrivalOrder() {
        let model = AppModel(listening: false)
        var slow = Flow.fixture(sequence: 1, status: 500); slow.duration = 3
        var fast = Flow.fixture(sequence: 2, host: "a.example.com", status: 200); fast.duration = 0.1
        var pending = Flow.fixture(sequence: 3, status: nil); pending.duration = nil; pending.state = .pending
        var failed = Flow.fixture(sequence: 4, status: nil); failed.duration = 1
        [slow, fast, pending, failed].forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        #expect(model.visibleFlows.map(\.sequence) == [1, 2, 3, 4], "arrival order by default")

        model.sortOrder = [KeyPathComparator(\Flow.sortDuration)]
        #expect(model.visibleFlows.map(\.sequence) == [2, 4, 1, 3], "unfinished requests sort as the longest")
        model.sortOrder = [KeyPathComparator(\Flow.sortStatus, order: .reverse)]
        #expect(model.visibleFlows.first?.sequence == 1, "500 first when descending")
        #expect(model.visibleFlows.last?.sequence == 4, "a failure without a response sorts below everything")
        model.sortOrder = [KeyPathComparator(\Flow.sortURL)]
        #expect(model.visibleFlows.first?.request.host == "a.example.com")

        // A filter and a sort together, and new traffic lands in sorted position.
        model.query.statusClasses = [2, 5]
        model.sortOrder = [KeyPathComparator(\Flow.sortDuration, order: .reverse)]
        #expect(model.visibleFlows.map(\.sequence) == [1, 2])
        var medium = Flow.fixture(sequence: 5, status: 201); medium.duration = 1
        model.enqueue(.added(medium)); model.flushEvents()
        #expect(model.visibleFlows.map(\.sequence) == [1, 5, 2])

        model.sortOrder = [KeyPathComparator(\Flow.sequence)]
        #expect(model.visibleFlows.map(\.sequence) == [1, 2, 5])
    }

    @Test
    func hidingAppleTrafficRefreshesTheList() {
        let model = AppModel(listening: false)
        model.settings.hideAppleTraffic = false
        [Flow.fixture(sequence: 1, host: "gateway.icloud.com", status: 200), .fixture(sequence: 2, status: 200)]
            .forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        #expect(model.visibleFlows.count == 2)
        model.settings.hideAppleTraffic = true
        #expect(model.visibleFlows.map(\.sequence) == [2])
    }

    @Test
    func theProxyPortIsTheConfiguredOneUntilAPortIsBound() {
        let model = AppModel(listening: false)
        model.settings.port = 9123
        #expect(model.proxyPort == 9123)
    }

    @Test
    func statusLineUnderTheTitle() {
        let model = AppModel(listening: false)
        [Flow.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 500)]
            .forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        #expect(model.statusLine == "Not recording · 2 requests")
        model.sidebar = .errors
        #expect(model.statusLine == "Not recording · 1 of 2 requests")
        model.proxyError = "port in use"
        #expect(model.statusLine == "Failed to start · see Settings")
    }
}
