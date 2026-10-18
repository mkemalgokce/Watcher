import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct WebSocketComposerTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
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
        let engine = try WatcherEngine(directory: directory.url)
        let url = try #require(URL(string: "ws://127.0.0.1:\(origin.port)/chat?room=1"))
        try await engine.composeWebSocket(url: url, messages: ["ping1", "ping2"], listenFor: 1)
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

        let notWebSocket = try #require(URL(string: "http://x/"))
        await #expect(throws: (any Error).self) { try await engine.composeWebSocket(url: notWebSocket, messages: []) }
    }
}
