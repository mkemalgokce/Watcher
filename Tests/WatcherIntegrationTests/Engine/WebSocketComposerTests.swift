import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct WebSocketComposerTests {
    private let waits = LockedBox<[Duration]>([])

    /// Listening is cut to a short real wait, enough for a loopback echo, and the asked-for length is recorded.
    private func engine() throws -> WatcherEngine {
        try WatcherEngine(
            directory: URL(fileURLWithPath: "/fake-home/.watcher"),
            files: FileAccessFake().access,
            sleep: { [waits] duration in
                waits.mutate { $0.append(duration) }
                try await Task.sleep(for: .milliseconds(300))
            }
        )
    }

    @Test
    func composeRecordsTheHandshakeAndBothDirections() async throws {
        let origin = WebSocketEchoOrigin()
        try await origin.start()
        do {
            try await composeConversation(with: origin)
        } catch {
            await origin.stop()
            throw error
        }
        await origin.stop()
    }

    private func composeConversation(with origin: WebSocketEchoOrigin) async throws {
        let engine = try engine()
        let url = try #require(URL(string: "ws://127.0.0.1:\(origin.port)/chat?room=1"))
        try await engine.composeWebSocket(url: url, messages: ["ping1", "ping2"], listenFor: 4)
        #expect(waits.value == [.seconds(4)])
        let flow = try #require(engine.store.all.first)
        #expect(flow.request.path == "/chat?room=1")
        #expect(flow.response?.status == 101)
        #expect(flow.state == .completed)
        func payloads(_ direction: WebSocketMessage.Direction) -> [String?] {
            flow.webSocketMessages.filter { $0.direction == direction }
                .map { String(bytes: $0.payload, encoding: .utf8) }
        }
        #expect(payloads(.clientToServer) == ["ping1", "ping2"])
        #expect(payloads(.serverToClient) == ["ping1", "ping2"])
    }

    @Test
    func aURLThatIsNotAWebSocketIsRefusedUnrecorded() async throws {
        let engine = try engine()
        let notWebSocket = try #require(URL(string: "http://x/"))
        await #expect(throws: WatcherEngine.WebSocketComposeError.self) {
            try await engine.composeWebSocket(url: notWebSocket, messages: [])
        }
        #expect(engine.store.all.isEmpty)
    }

    @Test
    func aServerThatCannotBeReachedFailsTheFlowAndTheCall() async throws {
        let engine = try engine()
        let url = try #require(URL(string: "ws://127.0.0.1:\(freeLoopbackPort())/"))
        await #expect(throws: (any Error).self) { try await engine.composeWebSocket(url: url, messages: ["hello"]) }
        let flow = try #require(engine.store.all.first)
        #expect(flow.state == .failed)
        #expect(flow.error != nil)
    }
}
