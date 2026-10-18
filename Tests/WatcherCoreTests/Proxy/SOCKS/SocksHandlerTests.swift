import AsyncHTTPClient
import Foundation
import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// The SOCKS5 handshake, driven through a testing channel against a stubbed upstream: no sockets.
@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct SocksHandlerTests {
    private static let greeting: [UInt8] = [5, 1, 0]
    private static let connect: [UInt8] = [5, 1, 0, 1, 10, 0, 0, 1, 0, 80]
    private static let success: [UInt8] = [5, 0, 0, 1, 0, 0, 0, 0, 0, 0]

    private func channel() async throws -> NIOAsyncTestingChannel {
        let directory = URL(fileURLWithPath: "/fake-home/.watcher")
        let authority = try CertificateAuthority(directory: directory, files: FileAccessFake().access)
        let upstream = UpstreamStub {
            let body = HTTPClientResponse.Body.bytes(ByteBuffer(string: "ok"))
            return HTTPClientResponse(status: .created, headers: ["Content-Length": "2"], body: body)
        }
        let channel = NIOAsyncTestingChannel()
        let server = ProxyServer(authority: authority, upstream: upstream)
        try await channel.pipeline.addHandler(SocksHandler(server: server))
        return channel
    }

    private func send(_ bytes: [UInt8], to channel: NIOAsyncTestingChannel) async throws {
        try await channel.writeInbound(ByteBuffer(bytes: bytes))
    }

    private func replies(of channel: NIOAsyncTestingChannel) async throws -> [UInt8] {
        var bytes: [UInt8] = []
        while let buffer = try await channel.readOutbound(as: ByteBuffer.self) {
            bytes += buffer.readableBytesView
        }
        return bytes
    }

    @Test
    func aGreetingOffersNoAuthenticationAndAwaitsTheRequest() async throws {
        let channel = try await channel()
        try await send(Self.greeting, to: channel)
        #expect(try await replies(of: channel) == [5, 0])
    }

    @Test
    func aGreetingSplitAcrossTwoReadsIsAnsweredOnce() async throws {
        let channel = try await channel()
        try await send([5, 2], to: channel)
        #expect(try await replies(of: channel).isEmpty)
        try await send([1, 0], to: channel)
        #expect(try await replies(of: channel) == [5, 0])
    }

    @Test
    func theMethodZeroMayBeAnyOfSeveralOffered() async throws {
        let channel = try await channel()
        try await send([5, 3, 2, 1, 0], to: channel)
        #expect(try await replies(of: channel) == [5, 0])
    }

    @Test
    func aGreetingWithoutNoAuthenticationIsRefusedAndClosed() async throws {
        let channel = try await channel()
        try await send([5, 1, 2], to: channel)
        #expect(try await replies(of: channel) == [5, 0xFF])
        try await channel.closeFuture.get()
    }

    @Test
    func anotherVersionIsClosedWithoutAnswer() async throws {
        let channel = try await channel()
        try await send([4, 1, 0], to: channel)
        #expect(try await replies(of: channel).isEmpty)
        try await channel.closeFuture.get()
    }

    @Test
    func aGreetingAndARequestInOneReadAreBothAnswered() async throws {
        let channel = try await channel()
        try await send(Self.greeting + Self.connect, to: channel)
        #expect(try await replies(of: channel) == [5, 0] + Self.success)
    }

    @Test
    func aRequestSplitAcrossReadsWaitsForTheRest() async throws {
        let channel = try await channel()
        try await send(Self.greeting + Self.connect.prefix(6), to: channel)
        #expect(try await replies(of: channel) == [5, 0])
        try await send(Array(Self.connect.dropFirst(6)), to: channel)
        #expect(try await replies(of: channel) == Self.success)
    }

    @Test(arguments: [(UInt8(2), UInt8(7)), (3, 7), (1, 8)])
    func anUnsupportedRequestIsRefusedWithItsReplyCodeAndClosed(command: UInt8, code: UInt8) async throws {
        let channel = try await channel()
        let type: UInt8 = command == 1 ? 9 : 1
        try await send(Self.greeting + [5, command, 0, type, 10, 0, 0, 1, 0, 80], to: channel)
        #expect(try await replies(of: channel) == [5, 0, 5, code, 0, 1, 0, 0, 0, 0, 0, 0])
        try await channel.closeFuture.get()
    }

    @Test
    func theBytesSentAfterTheRequestAreServedAsPlainHTTP() async throws {
        let channel = try await channel()
        try await send(Self.greeting + Self.connect, to: channel)
        _ = try await replies(of: channel)
        try await send(Array("GET /soc HTTP/1.1\r\nHost: h.test\r\n\r\n".utf8), to: channel)
        let reply = try await channel.waitForOutboundWrite(as: ByteBuffer.self)
        #expect(String(buffer: reply).hasPrefix("HTTP/1.1 201"))
    }
}
