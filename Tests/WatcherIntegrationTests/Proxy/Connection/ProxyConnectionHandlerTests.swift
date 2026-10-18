import AsyncHTTPClient
import Foundation
import NIO
import NIOSSL
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// CONNECT handling end to end: an HTTPS origin signed by a test authority, a proxy that trusts only that authority
/// upstream, and a client that trusts only Watcher's root (or, through a blind tunnel, only the origin's).
@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network), .serialized)
struct ProxyConnectionHandlerTests {
    private let origins: OriginAuthority
    private let files = FileAccessFake()

    init() throws {
        origins = try OriginAuthority()
    }

    private func withProxy(
        configure: @escaping (inout WatcherSettings) -> Void = { _ in },
        _ body: (WatcherEngine, _ proxyPort: Int, _ originPort: Int) async throws -> Void
    ) async throws {
        let upstream = try TestUpstream(tls: origins.serverContext(for: "secure.test"))
        try await upstream.start()
        let trust = try origins.trust
        let engine = try WatcherEngine(directory: URL(fileURLWithPath: "/fake-home/.watcher"), files: files.access) {
            ProxyServer(store: $0, authority: $1, upstreamTLS: trust, clientApp: { _ in nil })
        }
        do {
            try engine.settings.update {
                let spoof = DNSSpoofRule(host: "secure.test", address: "127.0.0.1")
                $0.dnsSpoofing = RuleSet(isEnabled: true, rules: [spoof])
                configure(&$0)
            }
            let proxyPort = try await engine.start(port: 0)
            try await body(engine, proxyPort, upstream.port)
        } catch {
            try? await engine.stop(); await upstream.stop()
            throw error
        }
        try await engine.stop(); await upstream.stop()
    }

    /// GET through the proxy, over HTTP/1.1 unless `httpVersion` lets the client offer h2, trusting only `trust`.
    private func get(
        _ url: String,
        proxyPort: Int,
        trust: TLSConfiguration,
        httpVersion: HTTPClient.Configuration.HTTPVersion = .http1Only
    ) async throws -> (Int, String) {
        var configuration = HTTPClient.Configuration(
            tlsConfiguration: trust,
            proxy: .server(host: "127.0.0.1", port: proxyPort)
        )
        configuration.httpVersion = httpVersion
        let client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
        do {
            let response = try await client.execute(HTTPClientRequest(url: url), timeout: .seconds(10))
            let body = try await response.body.collect(upTo: 1 << 20)
            try await client.shutdown()
            return (Int(response.status.code), String(buffer: body))
        } catch {
            try? await client.shutdown()
            throw error
        }
    }

    @Test
    func aDecryptedRequestReachesAnHTTPSOriginAndIsRecordedWithItsTLS() async throws {
        try await withProxy { engine, proxyPort, originPort in
            let trust = try OriginAuthority.trusting(engine.authority)
            let url = "https://secure.test:\(originPort)/secret"
            let (status, body) = try await get(url, proxyPort: proxyPort, trust: trust)
            #expect(status == 200)
            #expect(body.hasPrefix("GET /secret host=secure.test:\(originPort)"))
            let flow = try #require(engine.store.all.first)
            #expect(flow.request.scheme == "https")
            #expect(flow.request.port == originPort)
            #expect(flow.clientTLS?.isEmpty == false)
            #expect(flow.response?.status == 200)
        }
    }

    @Test
    func anHTTP2RequestReachesTheOriginOnTheTunnelledPort() async throws {
        try await withProxy { engine, proxyPort, originPort in
            let trust = try OriginAuthority.trusting(engine.authority)
            let url = "https://secure.test:\(originPort)/h2"
            let (status, body) = try await get(url, proxyPort: proxyPort, trust: trust, httpVersion: .automatic)
            #expect(status == 200)
            #expect(body.hasPrefix("GET /h2 host=secure.test:\(originPort)"))
            let flow = try #require(engine.store.all.first)
            #expect(flow.request.port == originPort)
            #expect(flow.clientTLS?.contains("h2") == true)
        }
    }

    @Test
    func anExcludedHostIsTunnelledBlindAndNotRecorded() async throws {
        try await withProxy(configure: { $0.sslProxying.exclude = ["secure.test"] }) { engine, proxyPort, originPort in
            let (status, body) = try await get(
                "https://secure.test:\(originPort)/private",
                proxyPort: proxyPort,
                trust: origins.trust
            )
            #expect(status == 200, "the client sees the origin's own certificate")
            #expect(body.hasPrefix("GET /private"))
            #expect(!engine.store.all.contains { $0.request.path == "/private" })
        }
    }

    @Test
    func aBlindTunnelToAClosedPortIsAnswered502() async throws {
        try await withProxy(configure: { $0.sslProxying.exclude = ["127.0.0.1"] }) { _, proxyPort, _ in
            let closed = try freeLoopbackPort()
            let client = RawClient()
            try await client.connect(port: proxyPort)
            try await client.send("CONNECT 127.0.0.1:\(closed) HTTP/1.1\r\nHost: 127.0.0.1:\(closed)\r\n\r\n")
            let reply = await client.received(containing: "failed")
            await client.close()
            #expect(reply.hasPrefix("HTTP/1.1 502"))
            #expect(reply.contains("Tunnel to 127.0.0.1:\(closed) failed"))
        }
    }

    @Test
    func aCONNECTWithoutAHostIsAnswered400() async throws {
        try await withProxy { _, proxyPort, _ in
            let client = RawClient()
            try await client.connect(port: proxyPort)
            try await client.send("CONNECT :443 HTTP/1.1\r\nHost: x\r\n\r\n")
            let reply = await client.received(containing: "\r\n\r\n")
            await client.close()
            #expect(reply.hasPrefix("HTTP/1.1 400"))
        }
    }

    @Test(arguments: ["", ":8080"])
    func aRequestWhoseHostHeaderNamesNoHostIsAnswered400(host: String) async throws {
        try await withProxy { _, proxyPort, _ in
            let client = RawClient()
            try await client.connect(port: proxyPort)
            try await client.send("GET /x HTTP/1.1\r\nHost: \(host)\r\n\r\n")
            let reply = await client.received(containing: "\r\n\r\n")
            await client.close()
            #expect(reply.hasPrefix("HTTP/1.1 400"), "\(reply)")
        }
    }
}
