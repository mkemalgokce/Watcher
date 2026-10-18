import AsyncHTTPClient
import Foundation
import NIO
import NIOHTTP1
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct ResponseWriterTests {
    private static let response = ResponseRecord(
        status: 201,
        headers: [Header("Content-Type", "text/plain"), Header("Transfer-Encoding", "chunked"), Header("X-Kept", "1")],
        body: Data("hello".utf8)
    )

    private func head(_ method: HTTPMethod = .GET, keepAlive: Bool = true) -> HTTPRequestHead {
        HTTPRequestHead(version: .http1_1, method: method, uri: "/", headers: keepAlive ? [:] : ["Connection": "close"])
    }

    private func connected() async throws -> NIOAsyncTestingChannel {
        let channel = NIOAsyncTestingChannel()
        try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).get()
        return channel
    }

    private func parts(of channel: NIOAsyncTestingChannel) async throws -> [HTTPServerResponsePart] {
        var parts: [HTTPServerResponsePart] = []
        while let part = try await channel.readOutbound(as: HTTPServerResponsePart.self) {
            parts.append(part)
        }
        return parts
    }

    private func headers(in parts: [HTTPServerResponsePart]) throws -> HTTPResponseHead {
        guard case let .head(head) = parts.first else { throw TestSupportError("no response head in \(parts)") }
        return head
    }

    private func body(in parts: [HTTPServerResponsePart]) -> Data {
        parts.reduce(into: Data()) { data, part in
            if case let .body(.byteBuffer(buffer)) = part {
                data.append(contentsOf: buffer.readableBytesView)
            }
        }
    }

    @Test
    func aBufferedAnswerCarriesItsLengthAndDropsConnectionHeaders() async throws {
        let channel = try await connected()
        ResponseWriter(isHTTP2: false).respond(Self.response, to: channel, head: head())
        let parts = try await parts(of: channel)
        let head = try headers(in: parts)
        #expect(head.status.code == 201)
        #expect(head.headers["Content-Length"] == ["5"])
        #expect(head.headers["Transfer-Encoding"].isEmpty)
        #expect(head.headers["X-Kept"] == ["1"])
        #expect(head.headers["Connection"] == ["keep-alive"])
        #expect(body(in: parts) == Data("hello".utf8))
        #expect(channel.isActive)
    }

    @Test
    func anAnswerToAHEADRequestHasNoBody() async throws {
        let channel = try await connected()
        ResponseWriter(isHTTP2: false).respond(Self.response, to: channel, head: head(.HEAD))
        let parts = try await parts(of: channel)
        #expect(try headers(in: parts).headers["Content-Length"] == ["5"])
        #expect(body(in: parts).isEmpty)
    }

    @Test
    func aClientThatAskedToCloseIsDisconnectedAfterTheAnswer() async throws {
        let channel = try await connected()
        ResponseWriter(isHTTP2: false).respond(Self.response, to: channel, head: head(keepAlive: false))
        #expect(try await headers(in: parts(of: channel)).headers["Connection"] == ["close"])
        try await channel.closeFuture.get()
    }

    @Test
    func anHTTP2StreamGetsNoConnectionHeader() async throws {
        let channel = try await connected()
        ResponseWriter(isHTTP2: true).respond(Self.response, to: channel, head: head(keepAlive: false))
        #expect(try await headers(in: parts(of: channel)).headers["Connection"].isEmpty)
        #expect(channel.isActive, "an HTTP/2 stream stays open whatever the request said")
    }

    @Test
    func aStreamedAnswerIsRelayedWithoutALengthAndReportedWhole() async throws {
        let channel = try await connected()
        let captured = LockedBox<(Data, Bool)?>(nil)
        await ResponseWriter(isHTTP2: false).stream(
            Self.response,
            body: .bytes(ByteBuffer(string: "streamed")),
            to: channel,
            head: head()
        ) { data, error in captured.mutate { $0 = (data, error == nil) } }
        let parts = try await parts(of: channel)
        #expect(try headers(in: parts).headers["Content-Length"].isEmpty)
        #expect(body(in: parts) == Data("streamed".utf8))
        #expect(captured.value?.0 == Data("streamed".utf8))
        #expect(captured.value?.1 == true)
    }
}
