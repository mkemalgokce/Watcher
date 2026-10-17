import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// Observers rebuild the list from events, so they must arrive in the order the store applied the changes.
@Suite(.tags(.unit))
struct FlowStoreEventOrderTests {
    private let iterations = 500

    @Test
    func concurrentBeginsAreObservedInSequenceOrder() async {
        let store = FlowStore()
        let events = store.events()

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = store.begin(.fixture(scheme: "http", host: "example.test", port: 80))
        }

        var added: [Flow] = []
        for await event in events {
            if case let .added(flow) = event {
                added.append(flow)
            }
            if added.count == iterations {
                break
            }
        }
        #expect(added.map(\.sequence) == Array(1 ... iterations))
        #expect(added.map(\.startedAt) == added.map(\.startedAt).sorted())
    }

    @Test
    func concurrentWebSocketMessagesAreObservedInOrder() async {
        let store = FlowStore()
        let flow = store.begin(.fixture(scheme: "ws", host: "example.test", port: 80))
        let events = store.events()

        let message = WebSocketMessage(direction: .serverToClient, kind: .text, payload: Data("x".utf8))
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            store.appendWebSocketMessage(message, to: flow.id)
        }

        var counts: [Int] = []
        for await event in events {
            if case let .updated(updated) = event {
                counts.append(updated.webSocketMessages.count)
            }
            if counts.count == iterations {
                break
            }
        }
        #expect(counts == Array(1 ... iterations))
    }
}
