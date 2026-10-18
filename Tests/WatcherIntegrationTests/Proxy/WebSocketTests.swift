import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct WebSocketTests {
    @Test
    func upgradeIsRecordedAndBytesAreRelayedBothWays() async throws {
        let origin = UpgradeOrigin()
        try await origin.start()
        do {
            try await relayThroughTheProxy(to: origin)
        } catch {
            await origin.stop()
            throw error
        }
        await origin.stop()
    }

    private func relayThroughTheProxy(to origin: UpgradeOrigin) async throws {
        try await withHarness { harness in
            let client = RawClient()
            try await client.connect(port: harness.proxyPort)
            try await client.send(
                "GET http://127.0.0.1:\(origin.port)/ws HTTP/1.1\r\nHost: 127.0.0.1:\(origin.port)\r\n"
                    + "Upgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
            )
            let handshake = await client.received(containing: "101 Switching Protocols")
            #expect(handshake.contains("101 Switching Protocols"), "\(handshake)")

            try await client.send("hello-frames")
            let echoed = await client.received(containing: "hello-frames")
            #expect(echoed.hasSuffix("hello-frames"), "\(echoed)")
            await client.close()

            let flow = try #require(harness.engine.store.all.first)
            #expect(flow.response?.status == 101)
            #expect(flow.request.path == "/ws")
        }
    }

    @Test
    func messagesAreDecodedBothWays() async throws {
        let origin = UpgradeOrigin()
        try await origin.start()
        do {
            try await exchangeAFrame(with: origin)
        } catch {
            await origin.stop()
            throw error
        }
        await origin.stop()
    }

    private func exchangeAFrame(with origin: UpgradeOrigin) async throws {
        try await withHarness { harness in
            let client = RawClient()
            try await client.connect(port: harness.proxyPort)
            try await client.send(
                "GET http://127.0.0.1:\(origin.port)/ws HTTP/1.1\r\nHost: x\r\n"
                    + "Upgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
            )
            _ = await client.received(containing: "101 Switching Protocols")
            // Masked text frame "hi" (key 01 02 03 04); the origin echoes the same bytes back.
            try await client.send(bytes: [0x81, 0x82, 1, 2, 3, 4, UInt8(ascii: "h") ^ 1, UInt8(ascii: "i") ^ 2])

            _ = await eventually(timeout: 3, poll: .milliseconds(50)) {
                (harness.engine.store.all.first?.webSocketMessages.count ?? 0) >= 2
            }
            let messages = harness.engine.store.all.first?.webSocketMessages ?? []
            await client.close()
            #expect(messages.map(\.direction) == [.clientToServer, .serverToClient])
            #expect(messages.map { String(bytes: $0.payload, encoding: .utf8) } == ["hi", "hi"])
            #expect(messages.first?.kind == .text)
        }
    }
}
