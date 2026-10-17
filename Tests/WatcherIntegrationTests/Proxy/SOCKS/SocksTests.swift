import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.integration, .network))
struct SocksTests {
    @Test
    func plainHTTPThroughSocks5IsRecorded() async throws {
        let socksPort = try freeLoopbackPort()
        try await withHarness(configure: { $0.socks = SocksSettings(isEnabled: true, port: socksPort) }) { harness in
            let client = RawClient()
            try await client.connect(port: socksPort)
            try await client.send(bytes: [5, 1, 0])
            let port = harness.upstream.port
            try await client.send(bytes: [5, 1, 0, 1, 127, 0, 0, 1, UInt8(port >> 8), UInt8(port & 0xFF)])
            let handshake = await client.receivedBytes(atLeast: 12)
            #expect(handshake == [5, 0, 5, 0, 0, 1, 0, 0, 0, 0, 0, 0])

            try await client.send("GET /socks HTTP/1.1\r\nHost: x\r\n\r\n")
            let reply = await client.received(containing: "GET /socks")
            #expect(reply.contains("200 OK") && reply.contains("GET /socks"), "\(reply)")
            await client.close()
            #expect(harness.engine.store.all.first?.request.url == "http://127.0.0.1:\(port)/socks")
        }
    }
}
