@testable import WatcherCore
import XCTest

/// Observers rebuild the list from events, so they must arrive in the order the store applied the changes.
final class FlowStoreEventOrderTests: XCTestCase {
    private let iterations = 500

    func testConcurrentBeginsAreObservedInSequenceOrder() async {
        let store = FlowStore()
        let events = store.events()

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = store.begin(RequestRecord(method: "GET", scheme: "http", host: "example.test", port: 80, path: "/"))
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
        XCTAssertEqual(added.map(\.sequence), Array(1 ... iterations))
        XCTAssertEqual(added.map(\.startedAt), added.map(\.startedAt).sorted())
    }

    func testConcurrentWebSocketMessagesAreObservedInOrder() async {
        let store = FlowStore()
        let flow = store.begin(RequestRecord(method: "GET", scheme: "ws", host: "example.test", port: 80, path: "/"))
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
        XCTAssertEqual(counts, Array(1 ... iterations))
    }
}
