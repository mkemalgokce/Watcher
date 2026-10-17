import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.integration, .network))
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
}
