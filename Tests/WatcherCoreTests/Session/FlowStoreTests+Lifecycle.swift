import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension FlowStoreTests {
    struct Lifecycle {
        private let store = FlowStore()

        @Test
        func aFlowBegunWhilePausedIsNeitherKeptNorUpdated() {
            store.isRecording = false
            let flow = store.begin(.fixture())
            store.update(flow.id) { $0.comment = "late" }
            #expect(store.all.isEmpty)
        }

        @Test
        func discardKeepsTheOrderOfTheRest() {
            let flows = ["/a", "/b", "/c", "/d"].map { store.begin(.fixture(path: $0)) }
            store.discard([flows[1].id, flows[3].id])
            #expect(store.all.map(\.request.path) == ["/a", "/c"])
        }

        @Test
        func loadRenumbersFromOne() {
            _ = store.begin(.fixture(path: "/old"))
            store.load([Flow.fixture(sequence: 7), Flow.fixture(sequence: 3)])
            #expect(store.all.map(\.sequence) == [1, 2])
        }

        @Test
        func loadKeepsOnlyTheNewestWithinTheLimit() {
            store.maxFlows = 1
            let newest = Flow.fixture(sequence: 2)
            store.load([Flow.fixture(sequence: 1), newest])
            #expect(store.all.map(\.id) == [newest.id])
            #expect(store.all.first?.sequence == 2)
        }

        @Test(arguments: [(-5, 0), (0, 0), (3, 3)])
        func aNegativeLimitMeansNoLimit(limit: Int, stored: Int) {
            store.maxFlows = limit
            #expect(store.maxFlows == stored)
        }

        @Test
        func aWebSocketKeepsOnlyItsNewestMessages() {
            let flow = store.begin(.fixture(scheme: "ws"))
            for index in 0 ... FlowStore.maxWebSocketMessages {
                let message = WebSocketMessage(direction: .clientToServer, kind: .text, payload: Data("\(index)".utf8))
                store.appendWebSocketMessage(message, to: flow.id)
            }
            let messages = store.all.first?.webSocketMessages ?? []
            #expect(messages.count == FlowStore.maxWebSocketMessages)
            #expect(messages.first?.payload == Data("1".utf8))
        }
    }
}

private func removedID(_ events: inout AsyncStream<FlowEvent>.Iterator) async -> UUID? {
    guard case let .removed(id)? = await events.next() else { return nil }
    return id
}

extension FlowStoreTests.Lifecycle {
    @Test
    func loweringTheLimitTrimsAtOnceAndPublishesWhatWasDropped() async {
        let store = FlowStore()
        let flows = (1 ... 5).map { store.begin(.fixture(path: "/\($0)")) }
        var events = store.events().makeAsyncIterator()
        store.maxFlows = 3
        #expect(store.all.map(\.request.path) == ["/3", "/4", "/5"])
        #expect(await removedID(&events) == flows[0].id)
        #expect(await removedID(&events) == flows[1].id)
    }

    @Test
    func raisingOrClearingTheLimitDropsNothing() {
        let store = FlowStore()
        store.maxFlows = 2
        _ = (1 ... 2).map { store.begin(.fixture(path: "/\($0)")) }
        store.maxFlows = 10
        store.maxFlows = 0
        store.maxFlows = -4
        #expect(store.all.count == 2)
    }

    @Test
    func discardingAnUnknownFlowPublishesNothing() async {
        let store = FlowStore()
        let kept = store.begin(.fixture())
        var events = store.events().makeAsyncIterator()
        store.discard(UUID())
        store.discard(kept.id)
        #expect(await removedID(&events) == kept.id)
    }

    @Test
    func aFlowBegunWhilePausedStillTakesASequenceNumber() {
        let store = FlowStore()
        store.isRecording = false
        _ = store.begin(.fixture())
        store.isRecording = true
        #expect(store.begin(.fixture()).sequence == 2)
    }
}

@Suite(.tags(.unit))
struct FlowStoreBodyBudgetTests {
    private func store(budget: Int) -> FlowStore {
        let store = FlowStore()
        store.maxBodyBytes = budget
        return store
    }

    private func add(_ store: FlowStore, _ path: String, bytes: Int) -> Flow {
        let flow = store.begin(.fixture(path: path))
        store.update(flow.id) { $0.response = .fixture(body: Data(count: bytes)) }
        return flow
    }

    @Test
    func theOldestRequestsGoWhenBodiesOutgrowTheBudget() {
        let store = store(budget: 100)
        let flows = (1 ... 4).map { add(store, "/\($0)", bytes: 40) }
        #expect(store.all.map(\.id) == flows.suffix(2).map(\.id))
    }

    @Test
    func theNewestRequestStaysEvenWhenItAloneIsOverBudget() {
        let store = store(budget: 10)
        let big = add(store, "/big", bytes: 500)
        #expect(store.all.map(\.id) == [big.id])
    }

    @Test
    func aBodyThatArrivesLateCountsTowardTheBudget() {
        let store = store(budget: 100)
        let early = store.begin(.fixture(path: "/early"))
        let late = add(store, "/late", bytes: 150)
        #expect(store.all.map(\.id) == [late.id])
        #expect(!store.all.contains { $0.id == early.id })
    }

    @Test
    func discardedAndClearedFlowsReleaseTheirBytes() {
        let store = store(budget: 100)
        let first = add(store, "/1", bytes: 60)
        store.discard(first.id)
        let second = add(store, "/2", bytes: 60)
        #expect(store.all.map(\.id) == [second.id], "the discarded 60 bytes no longer count")
        store.clear()
        let third = add(store, "/3", bytes: 90)
        #expect(store.all.map(\.id) == [third.id])
    }

    @Test
    func zeroKeepsEveryBody() {
        let store = store(budget: 0)
        _ = (1 ... 3).map { add(store, "/\($0)", bytes: 1_000_000) }
        #expect(store.all.count == 3)
    }

    @Test
    func observersAreToldWhichRequestsWereDropped() async {
        let store = store(budget: 100)
        var events = store.events().makeAsyncIterator()
        let first = add(store, "/1", bytes: 80)
        _ = add(store, "/2", bytes: 80)
        var removed: [UUID] = []
        for _ in 0 ..< 5 {
            if case let .removed(id)? = await events.next() {
                removed.append(id)
            }
        }
        #expect(removed == [first.id])
    }
}

/// What pausing does to traffic already on its way: a request in flight still finishes, nothing new is added.
@Suite(.tags(.unit))
struct FlowStorePauseTests {
    private let store = FlowStore()

    private func message() -> WebSocketMessage {
        WebSocketMessage(direction: .serverToClient, kind: .text, payload: Data("tick".utf8))
    }

    @Test
    func aRequestInFlightWhenPausedStillGetsItsResponse() {
        let flow = store.begin(.fixture(path: "/slow"))
        store.isRecording = false
        store.update(flow.id) { $0.response = .fixture(status: 200) }
        #expect(store.all.first?.response?.status == 200, "it would stay pending forever otherwise")
    }

    @Test
    func aWebSocketFrameThatArrivesWhilePausedIsNotAdded() {
        let flow = store.begin(.fixture(path: "/socket"))
        store.appendWebSocketMessage(message(), to: flow.id)
        store.isRecording = false
        store.appendWebSocketMessage(message(), to: flow.id)
        store.appendWebSocketMessage(message(), to: flow.id)
        #expect(store.all.first?.webSocketMessages.count == 1)
    }

    @Test
    func framesAreAddedAgainOnceRecordingResumes() {
        let flow = store.begin(.fixture(path: "/socket"))
        store.isRecording = false
        store.appendWebSocketMessage(message(), to: flow.id)
        store.isRecording = true
        store.appendWebSocketMessage(message(), to: flow.id)
        #expect(store.all.first?.webSocketMessages.count == 1)
    }

    @Test
    func aPausedStoreSendsObserversNothingForNewTraffic() async {
        var events = store.events().makeAsyncIterator()
        store.isRecording = false
        _ = store.begin(.fixture(path: "/new"))
        store.isRecording = true
        let kept = store.begin(.fixture(path: "/kept"))
        guard case let .added(flow)? = await events.next() else {
            Issue.record("no event")
            return
        }
        #expect(flow.id == kept.id, "the first event is the request after resuming")
    }
}
