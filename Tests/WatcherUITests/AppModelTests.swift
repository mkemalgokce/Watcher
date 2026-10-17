import AppKit
import Foundation
@testable import WatcherCore
@testable import WatcherUI
import XCTest

/// How the window's model turns store events into what the list, sidebar and status bar show, and how it reports
/// loading, success, empty and error states.
@MainActor
final class AppModelTests: XCTestCase {
    private func flow(_ n: Int, host: String = "api.example.com", status: Int? = 200, starred: Bool = false, app: String? = nil) -> Flow {
        var flow = Flow(sequence: n, request: RequestRecord(method: "GET", scheme: "https", host: host, port: 443, path: "/\(n)", clientApp: app))
        if let status {
            flow.response = ResponseRecord(status: status, headers: [], body: Data(repeating: 0, count: 10)); flow.state = .completed
        } else {
            flow.state = .failed
        }
        flow.isStarred = starred
        return flow
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    // MARK: Event batching

    func testEventsAreAppliedTogetherInOrder() {
        let model = AppModel(listening: false)
        let flows = (1 ... 500).map { flow($0) }
        flows.forEach { model.enqueue(.added($0)) }
        XCTAssertTrue(model.flows.isEmpty, "nothing changes until the batch is flushed")
        model.flushEvents()
        XCTAssertEqual(model.flows.map(\.sequence), Array(1 ... 500))
        XCTAssertEqual(model.visibleFlows.count, 500)
    }

    func testUpdatesRemovalsAndClearInOneBatch() {
        let model = AppModel(listening: false)
        let a = flow(1), b = flow(2), c = flow(3)
        [a, b, c].forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        model.selection = b.id

        var changed = a; changed.comment = "edited"
        model.enqueue(.updated(changed))
        model.enqueue(.removed(b.id))
        model.enqueue(.added(flow(4)))
        model.flushEvents()
        XCTAssertEqual(model.flows.map(\.sequence), [1, 3, 4])
        XCTAssertEqual(model.flows.first?.comment, "edited")
        XCTAssertNil(model.selection, "a removed flow cannot stay selected")
        XCTAssertNil(model.selectedFlow)

        model.selection = c.id
        XCTAssertEqual(model.selectedFlow?.id, c.id, "the index is rebuilt after a removal")

        model.enqueue(.cleared)
        model.enqueue(.added(flow(9)))
        model.flushEvents()
        XCTAssertEqual(model.flows.map(\.sequence), [9])
        XCTAssertNil(model.selection)
    }

    func testUpdateForUnknownFlowIsIgnored() {
        let model = AppModel(listening: false)
        model.enqueue(.updated(flow(1)))
        model.enqueue(.removed(UUID()))
        model.flushEvents()
        XCTAssertTrue(model.flows.isEmpty)
    }

    /// Integration: the model follows a real store, and a burst of traffic reaches it as a batch, not one re-render per event.
    func testFollowsStoreInBatches() async {
        let model = AppModel(listening: false)
        model.observeEngine()
        model.engine.store.load((1 ... 2000).map { flow($0) })
        await waitUntil(model.flows.count == 2000)
        XCTAssertEqual(model.flows.last?.sequence, 2000)

        let started = Date()
        let ids = Set(model.flows.prefix(1000).map(\.id))
        model.delete(ids)
        await waitUntil(model.flows.count == 1000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "deleting a large selection must not be quadratic")
        XCTAssertTrue(model.flows.allSatisfy { !ids.contains($0.id) })
    }

    // MARK: Derived state

    func testSidebarAndQueryFilterTheList() {
        let model = AppModel(listening: false)
        [flow(1, starred: true, app: "Safari"), flow(2, status: 500, app: "curl"), flow(3, host: "cdn.other.org", status: nil), flow(4, status: 101)]
            .forEach { model.enqueue(.added($0)) }
        model.flushEvents()

        XCTAssertEqual(model.counts.starred, 1)
        XCTAssertEqual(model.counts.errors, 2)
        XCTAssertEqual(model.counts.webSocket, 1)
        XCTAssertEqual(Set(model.counts.apps.map(\.name)), ["Safari", "curl"])
        XCTAssertEqual(Set(model.counts.domains.map(\.name)), ["example.com", "other.org"])

        model.sidebar = .errors
        XCTAssertEqual(model.visibleFlows.map(\.sequence), [2, 3])
        model.sidebar = .domain("other.org")
        XCTAssertEqual(model.visibleFlows.map(\.sequence), [3])
        model.sidebar = .all
        model.query.text = "/4"
        XCTAssertEqual(model.visibleFlows.map(\.sequence), [4])
        XCTAssertEqual(model.visibleBytes, 10)
        model.query.reset()
        XCTAssertEqual(model.visibleFlows.count, 4)
    }

    func testSortingByAnyColumnAndBackToArrivalOrder() {
        let model = AppModel(listening: false)
        var slow = flow(1, status: 500); slow.duration = 3
        var fast = flow(2, host: "a.example.com", status: 200); fast.duration = 0.1
        var pending = flow(3, status: nil); pending.duration = nil; pending.state = .pending
        var failed = flow(4, status: nil); failed.duration = 1
        [slow, fast, pending, failed].forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        XCTAssertEqual(model.visibleFlows.map(\.sequence), [1, 2, 3, 4], "arrival order by default")

        model.sortOrder = [KeyPathComparator(\Flow.sortDuration)]
        XCTAssertEqual(model.visibleFlows.map(\.sequence), [2, 4, 1, 3], "unfinished requests sort as the longest")
        model.sortOrder = [KeyPathComparator(\Flow.sortStatus, order: .reverse)]
        XCTAssertEqual(model.visibleFlows.first?.sequence, 1, "500 first when descending")
        XCTAssertEqual(model.visibleFlows.last?.sequence, 4, "a failure without a response sorts below everything")
        model.sortOrder = [KeyPathComparator(\Flow.sortURL)]
        XCTAssertEqual(model.visibleFlows.first?.request.host, "a.example.com")

        // A filter and a sort together, and new traffic lands in sorted position.
        model.query.statusClasses = [2, 5]
        model.sortOrder = [KeyPathComparator(\Flow.sortDuration, order: .reverse)]
        XCTAssertEqual(model.visibleFlows.map(\.sequence), [1, 2])
        var medium = flow(5, status: 201); medium.duration = 1
        model.enqueue(.added(medium)); model.flushEvents()
        XCTAssertEqual(model.visibleFlows.map(\.sequence), [1, 5, 2])

        model.sortOrder = [KeyPathComparator(\Flow.sequence)]
        XCTAssertEqual(model.visibleFlows.map(\.sequence), [1, 2, 5])
    }

    func testHidingAppleTrafficRefreshesTheList() {
        let model = AppModel(listening: false)
        model.settings.hideAppleTraffic = false
        [flow(1, host: "gateway.icloud.com"), flow(2)].forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        XCTAssertEqual(model.visibleFlows.count, 2)
        model.settings.hideAppleTraffic = true
        XCTAssertEqual(model.visibleFlows.map(\.sequence), [2])
    }

    // MARK: Loading, success and error states

    func testSaveAndOpenSessionReportProgressAndResult() async {
        let model = AppModel(listening: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).watcher")
        defer { try? FileManager.default.removeItem(at: url) }

        let saving = Task { await model.write([flow(1), flow(2)], to: url) { try SessionFile.encode($0) } }
        await Task.yield()
        XCTAssertNotNil(model.busyMessage, "saving shows a busy state right away")
        await saving.value
        XCTAssertNil(model.busyMessage)
        XCTAssertEqual(model.notice?.kind, .success)

        await model.importFile(at: url)
        XCTAssertNil(model.busyMessage)
        XCTAssertEqual(model.notice?.kind, .success)
        XCTAssertEqual(model.notice?.message, "Opened 2 requests from \(url.lastPathComponent)")
        model.syncFromStore()
        XCTAssertEqual(model.flows.count, 2)
    }

    func testOpeningABrokenFileShowsAnError() async throws {
        let model = AppModel(listening: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID().uuidString).har")
        try Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await model.importFile(at: url)
        XCTAssertEqual(model.notice?.kind, .error)
        XCTAssertNil(model.busyMessage)
    }

    func testOpeningAnEmptySessionSaysSo() async throws {
        let model = AppModel(listening: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).watcher")
        try SessionFile.encode([]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await model.importFile(at: url)
        XCTAssertEqual(model.notice?.kind, .info)
        XCTAssertTrue(model.notice?.message.contains("no requests") == true)
    }

    /// Integration: a port that is already taken leaves a visible error and a retry, not a silent toolbar.
    func testProxyStartFailureIsShownUntilRetry() async throws {
        let first = AppModel(listening: false)
        let port = try await first.engine.start(port: 0)
        defer { Task { try? await first.engine.stop() } }

        let model = AppModel(listening: false)
        var settings = model.engine.settings.value
        settings.port = port; settings.autoSelectPort = false
        try model.engine.settings.replace(with: settings)
        model.settings = settings

        model.toggleRunning()
        XCTAssertTrue(model.isSwitchingProxy, "starting shows progress")
        model.toggleRunning() // a second click while starting is ignored
        await waitUntil(!model.isSwitchingProxy)
        XCTAssertFalse(model.isRunning)
        XCTAssertNotNil(model.proxyError)
        XCTAssertEqual(model.notice?.kind, .error)

        try await first.engine.stop()
        model.toggleRunning()
        XCTAssertNil(model.proxyError, "a new attempt clears the old error")
        await waitUntil(!model.isSwitchingProxy)
        XCTAssertTrue(model.isRunning)
        XCTAssertNil(model.proxyError)
        model.toggleRunning()
        await waitUntil(!model.isSwitchingProxy && !model.isRunning)
    }

    func testStatusLineUnderTheTitle() {
        let model = AppModel(listening: false)
        [flow(1), flow(2, status: 500)].forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        XCTAssertEqual(model.statusLine, "Not recording · 2 requests")
        model.sidebar = .errors
        XCTAssertEqual(model.statusLine, "Not recording · 1 of 2 requests")
        model.proxyError = "port in use"
        XCTAssertEqual(model.statusLine, "Failed to start · see Settings")
    }

    func testInvalidPortIsRefusedWithoutTryingToStart() {
        let model = AppModel(listening: false)
        for port in [0, -1, 65536] {
            model.settings.port = port
            model.toggleRunning()
            XCTAssertFalse(model.isSwitchingProxy, "\(port)")
            XCTAssertTrue(model.proxyError?.contains("not valid") == true, "\(port)")
        }
        XCTAssertTrue(PortRange.isValid(1)); XCTAssertTrue(PortRange.isValid(65535))
    }

    // MARK: Breakpoints

    private func hit(_ path: String) -> BreakpointCenter.Hit {
        .init(phase: .request, request: RequestRecord(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: path))
    }

    func testNewPausesAreAnnouncedNotOpened() {
        let model = AppModel(listening: false)
        model.breakpointsChanged([hit("/a")])
        XCTAssertNil(model.sheet, "a pause must never take over the window")
        XCTAssertEqual(model.notice?.kind, .info)
        model.dismissNotice()
        model.breakpointsChanged([])
        XCTAssertNil(model.notice, "a resolved pause is not announced")
    }

    func testRulesMatchingAPausedRequest() {
        let model = AppModel(listening: false)
        model.settings.breakpoints = RuleSet(isEnabled: true, rules: [
            BreakpointRule(name: "login", matching: MatchingRule(pattern: "api.example.com/login")),
            BreakpointRule(name: "off", isEnabled: false, matching: MatchingRule(pattern: "api.example.com/login")),
            BreakpointRule(name: "other", matching: MatchingRule(pattern: "other.example.com/*")),
        ])
        XCTAssertEqual(model.breakpointRules(matching: hit("/login").request).map(\.name), ["login"], "disabled and unrelated rules are ignored")
        XCTAssertTrue(model.breakpointRules(matching: hit("/elsewhere").request).isEmpty)
    }

    func testRemovingTheBreakpointOfAPausedRequest() {
        let model = AppModel(listening: false)
        model.settings.breakpoints = RuleSet(isEnabled: true, rules: [
            BreakpointRule(name: "login", matching: MatchingRule(pattern: "api.example.com/login")),
            BreakpointRule(name: "keep", matching: MatchingRule(pattern: "api.example.com/keep")),
        ])
        model.removeBreakpoints(for: hit("/login"))
        XCTAssertEqual(model.settings.breakpoints.rules.map(\.name), ["keep"])
        XCTAssertEqual(model.notice?.message, "Breakpoint “login” removed")
        // Removing for a request no rule matches only lets it continue and leaves the rules alone.
        model.removeBreakpoints(for: hit("/nothing"))
        XCTAssertEqual(model.settings.breakpoints.rules.map(\.name), ["keep"])
    }

    func testCompareOpensTheWindowWithABase() {
        let model = AppModel(listening: false)
        let base = flow(1)
        model.compare(withBase: base)
        XCTAssertEqual(model.diffBase?.id, base.id)
        XCTAssertEqual(model.compareWindowRequest, 1)
    }
}
