import NIO
import NIOHTTP1
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// The refusals a connection handler makes before anything leaves the machine, driven through a testing channel.
@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct ProxyConnectionHandlerTests {
    private func channel(
        bodyLimit: Int = ProxyServer.maxBodyBytes,
        isHTTP2: Bool = false
    ) async throws -> NIOAsyncTestingChannel {
        let server = ProxyServer(authority: nil, bodyLimit: bodyLimit)
        let channel = NIOAsyncTestingChannel()
        try await channel.pipeline.addHandler(
            ProxyConnectionHandler(server: server, codecs: [], origin: nil, isHTTP2: isHTTP2)
        )
        return channel
    }

    private func send(
        _ method: HTTPMethod,
        uri: String,
        body: [String] = [],
        to channel: NIOAsyncTestingChannel
    ) async throws {
        let head = HTTPRequestHead(version: .http1_1, method: method, uri: uri, headers: ["Host": "x.test"])
        try await channel.writeInbound(HTTPServerRequestPart.head(head))
        for chunk in body {
            try await channel.writeInbound(HTTPServerRequestPart.body(ByteBuffer(string: chunk)))
        }
        try await channel.writeInbound(HTTPServerRequestPart.end(nil))
    }

    private func answer(of channel: NIOAsyncTestingChannel) async throws -> (status: Int, body: String) {
        var status: Int?
        var body = ""
        while let part = try await channel.readOutbound(as: HTTPServerResponsePart.self) {
            switch part {
            case let .head(head): status = Int(head.status.code)
            case let .body(.byteBuffer(buffer)): body += String(buffer: buffer)
            default: break
            }
        }
        return try (#require(status, "nothing was answered"), body)
    }

    @Test
    func aBodyBeyondTheLimitIsAnswered413() async throws {
        let channel = try await channel(bodyLimit: 8)
        try await send(.POST, uri: "http://x.test/up", body: ["12345", "6789"], to: channel)
        let reply = try await answer(of: channel)
        #expect(reply.status == 413)
        #expect(reply.body == "Body too large for Watcher")
    }

    @Test
    func connectOnAnHTTP2StreamIsAnswered501() async throws {
        let channel = try await channel(isHTTP2: true)
        try await send(.CONNECT, uri: "x.test:443", to: channel)
        let reply = try await answer(of: channel)
        #expect(reply.status == 501)
        #expect(reply.body == "CONNECT is not supported over HTTP/2")
    }
}
