import AsyncHTTPClient
import Foundation
import NIO
import NIOHTTP1
import NIOSSL
import NIOTLS
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// What the server records about a decrypted connection, and which connections it decrypts at all.
@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct HTTP2SwitchTests {
    private func authority() throws -> CertificateAuthority {
        try CertificateAuthority(directory: URL(fileURLWithPath: "/fake-home/.watcher"), files: FileAccessFake().access)
    }

    @Test(arguments: [
        (TLSVersion.tlsv1, "TLS 1.0"), (.tlsv11, "TLS 1.1"), (.tlsv12, "TLS 1.2"), (.tlsv13, "TLS 1.3"),
    ])
    func eachTLSVersionHasItsName(version: TLSVersion, name: String) {
        #expect(ProxyServer.format(version) == name)
    }

    @Test
    func withoutAnAuthorityOrACustomCertificateNothingIsDecrypted() throws {
        let server = ProxyServer(authority: nil)
        #expect(!server.shouldIntercept(host: "a.test"))
        let handlers = try server.tlsHandlers(host: "a.test", port: 443, http1: [], details: ConnectionDetails())
        #expect(handlers.isEmpty)
    }

    @Test
    func withAnAuthorityTheTLSHandlerIsFollowedByTheProtocolSwitch() throws {
        let server = try ProxyServer(authority: authority())
        #expect(server.shouldIntercept(host: "a.test"))
        let handlers = try server.tlsHandlers(host: "a.test", port: 443, http1: [], details: ConnectionDetails())
        #expect(handlers.count == 2)
        #expect(handlers[0] is NIOSSLServerHandler)
        #expect(handlers[1] is ApplicationProtocolNegotiationHandler)
    }

    @Test(arguments: [nil, "http/1.1"] as [String?])
    func aConnectionThatDidNotNegotiateH2IsRecordedAsHTTP1(negotiated: String?) async throws {
        let details = ConnectionDetails()
        let server = ProxyServer(authority: nil)
        let channel = NIOAsyncTestingChannel()
        let negotiation = server.http2Switch(host: "a.test", port: 443, http1: [], details: details)
        try await channel.pipeline.addHandler(negotiation)
        try await channel.pipeline.fireUserInboundEventTriggered(
            TLSUserEvent.handshakeCompleted(negotiatedProtocol: negotiated)
        )
        #expect(await eventually { details.isHandshakeDone })
        #expect(details.summary == "http/1.1")
    }

    @Test
    func anH2StreamWithAnUpgradeHeaderIsForwardedNotUpgraded() async throws {
        let upstream = UpstreamStub { HTTPClientResponse(status: .ok, headers: ["Content-Length": "0"]) }
        let server = ProxyServer(authority: nil, upstream: upstream)
        let channel = NIOAsyncTestingChannel()
        let tunnel = TunnelTarget(scheme: "https", host: "a.test", port: 443)
        try await channel.pipeline.addHandler(
            ProxyConnectionHandler(server: server, codecs: [], origin: nil, tunnel: tunnel, isHTTP2: true)
        )
        let head = HTTPRequestHead(version: .http2, method: .GET, uri: "/ws", headers: ["Upgrade": "websocket"])
        try await channel.writeInbound(HTTPServerRequestPart.head(head))
        try await channel.writeInbound(HTTPServerRequestPart.end(nil))
        _ = try await channel.waitForOutboundWrite(as: HTTPServerResponsePart.self)
        #expect(upstream.sent.map(\.record.path) == ["/ws"])
        #expect(server.store.all.first?.response?.status == 200)
        try await server.stop()
    }
}
