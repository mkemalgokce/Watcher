import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// An outer engine that knows only an external proxy reaches `upstream.test`, which resolves inside the inner harness
/// alone (DNS Spoofing, blind tunnel).
@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct ExternalProxyTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    @Test
    func anHTTPProxyChainReachesAnOriginOnlyTheProxyKnows() async throws {
        try await withHarness(configure: { $0.sslProxying = SSLProxyingSettings(include: [], exclude: []) }) { inner in
            let response = try await send(
                chainedRequest("/via-proxy", to: inner),
                via: ExternalProxySettings(isEnabled: true, kind: .http, host: "127.0.0.1", port: inner.proxyPort)
            )
            #expect(response.status == 200)
            #expect(String(bytes: response.body, encoding: .utf8)?.hasPrefix("GET /via-proxy") == true)
        }
    }

    @Test
    func aPACFileAndASocksProxyBothReachTheInnerProxy() async throws {
        try await withHarness(configure: {
            $0.sslProxying = SSLProxyingSettings(include: [], exclude: [])
            $0.socks = SocksSettings(isEnabled: true, port: 0)
        }) { inner in
            let socksPort = try #require(inner.engine.socksPort)
            let request = chainedRequest("/chained", to: inner)

            // PAC loaded from a file:// URL points at the inner HTTP proxy.
            let pacFile = directory.appending("proxy.pac")
            let pac = "function FindProxyForURL(url, host) { "
                + "return shExpMatch(host, '*.test') ? 'PROXY 127.0.0.1:\(inner.proxyPort)' : 'DIRECT'; }"
            try Data(pac.utf8).write(to: pacFile)
            let pacResponse = try await send(
                request,
                via: ExternalProxySettings(isEnabled: true, kind: .pac, pacURL: pacFile.absoluteString)
            )
            #expect(pacResponse.status == 200)
            #expect(String(bytes: pacResponse.body, encoding: .utf8)?.hasPrefix("GET /chained") == true)

            // SOCKS: the inner engine's own SOCKS5 listener.
            let socksResponse = try await send(
                request,
                via: ExternalProxySettings(isEnabled: true, kind: .socks, host: "127.0.0.1", port: socksPort)
            )
            #expect(socksResponse.status == 200)
            #expect(String(bytes: socksResponse.body, encoding: .utf8)?.hasPrefix("GET /chained") == true)
        }
    }

    private func chainedRequest(_ path: String, to inner: Harness) -> RequestRecord {
        .fixture(scheme: "http", host: "upstream.test", port: inner.upstream.port, path: path)
    }

    /// Sends `request` from a fresh engine whose only route out is `external`, and stops that engine afterwards.
    private func send(_ request: RequestRecord, via external: ExternalProxySettings) async throws -> ResponseRecord {
        let outer = try WatcherEngine(directory: directory.appending(UUID().uuidString))
        try outer.settings.update { $0.externalProxy = external }
        try await outer.start(port: 0)
        let response = await outer.send(request)
        try await outer.stop()
        return response
    }
}
