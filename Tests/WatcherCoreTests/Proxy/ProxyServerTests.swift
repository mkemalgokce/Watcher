import AsyncHTTPClient
import Foundation
import NIOHTTP1
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ProxyServerTests {
    @Test(arguments: [100, 204, 304])
    func aStatusThatCannotHaveABodyIsNeverStreamed(status: Int) {
        let response = HTTPClientResponse(status: .init(statusCode: status))
        #expect(!ProxyServer.shouldStream(response))
    }

    @Test
    func aResponseWithoutALengthIsStreamed() {
        #expect(ProxyServer.shouldStream(HTTPClientResponse(status: .ok)))
    }

    @Test
    func theCertificatePageIsOfferedOnlyWithAnAuthority() async throws {
        let authority = try CertificateAuthority(
            directory: URL(fileURLWithPath: "/fake-home/.watcher"),
            files: FileAccessFake().access
        )
        let with = ProxyServer(authority: authority), without = ProxyServer(authority: nil)
        #expect(with.certificatePage != nil)
        #expect(without.certificatePage == nil)
        try await with.stop(); try await without.stop()
    }

    @Test
    func reapplyingUnchangedSettingsKeepsTheUpstreamClients() async throws {
        let server = ProxyServer(authority: nil)
        let settings = WatcherSettings()
        func apply() {
            server.updatePolicies(settings)
            server.updateUpstream(external: settings.externalProxy, pac: nil, dnsRules: [], certificates: [])
        }
        apply()
        let first = server.upstream.client(for: .fixture(host: "a.test"))
        apply()
        #expect(server.upstream.client(for: .fixture(host: "a.test")) === first)
        try await server.stop()
    }

    @Test
    func aKeyLogThatCouldNotBeCreatedIsRetriedForTheUpstreamClients() async throws {
        let files = FileAccessFake()
        let server = ProxyServer(authority: nil, files: files.access)
        var settings = WatcherSettings()
        settings.tlsKeyLogFile = "/logs/keys.log"
        files.fail(.appendPrivately)
        server.updatePolicies(settings)
        let withoutLog = server.upstream.client(for: .fixture(host: "a.test"))
        files.succeed(.appendPrivately)
        server.updatePolicies(settings)
        let withLog = server.upstream.client(for: .fixture(host: "a.test"))
        #expect(withLog !== withoutLog)
        server.updatePolicies(settings)
        #expect(server.upstream.client(for: .fixture(host: "a.test")) === withLog)
        try await server.stop()
    }

    @Test
    func anEventStreamIsStreamedWhateverItsLength() {
        let headers: HTTPHeaders = ["Content-Type": "text/event-stream", "Content-Length": "1"]
        #expect(ProxyServer.shouldStream(HTTPClientResponse(status: .ok, headers: headers)))
    }

    @Test(arguments: [(1, false), (ProxyServer.maxBodyBytes, true)])
    func aKnownLengthIsStreamedOnlyWhenLarge(length: Int, streamed: Bool) {
        let response = HTTPClientResponse(status: .ok, headers: ["Content-Length": "\(length)"])
        #expect(ProxyServer.shouldStream(response) == streamed)
    }
}
