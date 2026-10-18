import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct SocksHandlerTests {
    @Test
    func plainHTTPThroughSocks5IsRecorded() async throws {
        try await withHarness(configure: { $0.socks = SocksSettings(isEnabled: true, port: 0) }) { harness in
            let socksPort = try #require(harness.engine.socksPort)
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

    @Test
    func anExcludedHostIsRelayedBlindWithTheBytesSentAlongWithTheRequest() async throws {
        try await withHarness(configure: {
            $0.socks = SocksSettings(isEnabled: true, port: 0)
            $0.sslProxying.exclude = ["127.0.0.1"]
        }) { harness in
            let socksPort = try #require(harness.engine.socksPort)
            let client = RawClient()
            try await client.connect(port: socksPort)
            let port = harness.upstream.port
            let request = Array("GET /blind HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
            let greetingAndConnect: [UInt8] = [5, 1, 0, 5, 1, 0, 1, 127, 0, 0, 1, UInt8(port >> 8), UInt8(port & 0xFF)]
            try await client.send(bytes: greetingAndConnect + request)
            let reply = await client.received(containing: "GET /blind")
            await client.close()
            #expect(reply.contains("200 OK"), "\(reply)")
            #expect(harness.engine.store.all.isEmpty, "a blind relay is not decrypted or recorded")
        }
    }

    @Test
    func aHostThatCannotBeReachedGetsReplyCodeFive() async throws {
        let closed = try freeLoopbackPort()
        try await withHarness(configure: {
            $0.socks = SocksSettings(isEnabled: true, port: 0)
            $0.sslProxying.exclude = ["127.0.0.1"]
        }) { harness in
            let socksPort = try #require(harness.engine.socksPort)
            let client = RawClient()
            try await client.connect(port: socksPort)
            try await client.send(bytes: [5, 1, 0, 5, 1, 0, 1, 127, 0, 0, 1, UInt8(closed >> 8), UInt8(closed & 0xFF)])
            let reply = await client.receivedBytes(atLeast: 12)
            await client.close()
            #expect(reply == [5, 0, 5, 5, 0, 1, 0, 0, 0, 0, 0, 0])
        }
    }
}
