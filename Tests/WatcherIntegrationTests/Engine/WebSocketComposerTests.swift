import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct WebSocketComposerTests {
    private let waits = LockedBox<[Duration]>([])
    private let recorded = LockedBox<FlowStore?>(nil)
    private let ticks = LockedBox(0.0)

    /// Listening ends once both echoes are recorded, and the asked-for length is kept; the clock moves 2 s per reading.
    private func engine() throws -> WatcherEngine {
        let engine = try WatcherEngine(
            directory: URL(fileURLWithPath: "/fake-home/.watcher"),
            files: FileAccessFake().access,
            sleep: { [waits, recorded] duration in
                waits.mutate { $0.append(duration) }
                _ = await eventually {
                    recorded.value?.all.first?.webSocketMessages.filter { $0.direction == .serverToClient }.count == 2
                }
            },
            now: { [ticks] in
                ticks.mutate { $0 += 2 }
                return Date(timeIntervalSince1970: ticks.value)
            }
        )
        recorded.mutate { $0 = engine.store }
        return engine
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
        #expect(flow.duration == 2)
        func payloads(_ direction: WebSocketMessage.Direction) -> [String?] {
            flow.webSocketMessages.filter { $0.direction == direction }
                .map { String(bytes: $0.payload, encoding: .utf8) }
        }
        #expect(payloads(.clientToServer) == ["ping1", "ping2"])
        #expect(payloads(.serverToClient) == ["ping1", "ping2"])
    }

    @Test
    func theHandshakeIsRecordedWithItsEscapesIntact() async throws {
        let origin = WebSocketEchoOrigin()
        try await origin.start()
        let engine = try engine()
        let url = try #require(URL(string: "ws://127.0.0.1:\(origin.port)/a%20b?q=%20x"))
        do {
            try await engine.composeWebSocket(url: url, messages: ["ping1", "ping2"], listenFor: 4)
        } catch {
            await origin.stop()
            throw error
        }
        await origin.stop()
        #expect(engine.store.all.first?.request.path == "/a%20b?q=%20x")
    }

    @Test
    func aServerThatDoesNotUpgradeFailsTheFlowAndKeepsItsDuration() async throws {
        let origin = TestUpstream()
        try await origin.start()
        let engine = try engine()
        let url = try #require(URL(string: "ws://127.0.0.1:\(origin.port)/"))
        await #expect(throws: (any Error).self) { try await engine.composeWebSocket(url: url, messages: ["hello"]) }
        await origin.stop()
        let flow = try #require(engine.store.all.first)
        #expect(flow.state == .failed)
        #expect(flow.error != nil)
        #expect(flow.duration == 2)
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
        #expect(flow.duration == 2)
    }
}
