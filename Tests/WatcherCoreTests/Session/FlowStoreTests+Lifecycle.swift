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
