import AsyncHTTPClient
import Foundation
import NIOSSL
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProxyServerTests {
    /// An origin that listens on `[::1]`, reached through the proxy by its bracketed literal.
    @Suite(.timeLimit(.minutes(1)), .tags(.integration, .network), .ipv6Loopback)
    struct IPv6 {
        private let origins: OriginAuthority
        private let files = FileAccessFake()

        init() throws {
            origins = try OriginAuthority()
        }

        @Test
        func aPlainRequestToABracketedLiteralIsForwardedAndRecorded() async throws {
            try await withHarness(host: "::1", loopbackAddress: "::1") { harness in
                let (status, body) = try await harness.get("/plain")
                #expect(status == 200)
                #expect(body.hasPrefix("GET /plain host=[::1]:\(harness.upstream.port)"))
                let flow = try #require(harness.engine.store.all.first)
                #expect(flow.request.host == "::1")
                #expect(flow.request.port == harness.upstream.port)
            }
        }

        @Test
        func aRequestNamingTheOriginOnlyInItsBracketedHostHeaderIsForwarded() async throws {
            try await withHarness(host: "::1", loopbackAddress: "::1") { harness in
                let port = harness.upstream.port
                let client = RawClient()
                try await client.connect(port: harness.proxyPort)
                try await client.send("GET /named HTTP/1.1\r\nHost: [::1]:\(port)\r\nConnection: close\r\n\r\n")
                let answer = await client.received(containing: "bytes=")
                #expect(answer.contains("GET /named host=[::1]:\(port)"), "\(answer)")
                #expect(harness.engine.store.all.first?.request.host == "::1")
                await client.close()
            }
        }

        @Test
        func aBlindTunnelToABracketedLiteralRelaysTheBytesBothWays() async throws {
            try await withHarness(
                host: "::1", loopbackAddress: "::1", configure: { $0.sslProxying.exclude = ["::1"] }
            ) { harness in
                let port = harness.upstream.port
                let client = RawClient()
                try await client.connect(port: harness.proxyPort)
                try await client.send("CONNECT [::1]:\(port) HTTP/1.1\r\nHost: [::1]:\(port)\r\n\r\n")
                #expect(await client.received(containing: "200").hasPrefix("HTTP/1.1 200"))
                try await client.send("GET /tunnel HTTP/1.1\r\nHost: [::1]:\(port)\r\nConnection: close\r\n\r\n")
                let answer = await client.received(containing: "bytes=")
                #expect(answer.contains("GET /tunnel host=[::1]:\(port)"), "\(answer)")
                await client.close()
            }
        }

        @Test
        func aDecryptedTunnelToABracketedLiteralIsInspected() async throws {
            try await withHarness(host: "::1", origin: origins, files: files, loopbackAddress: "::1") { harness in
                var trust = try OriginAuthority.trusting(harness.engine.authority)
                // The client names an IP address; what is under test is the relay, not name matching.
                trust.certificateVerification = .noHostnameVerification
                let port = harness.upstream.port
                let client = HTTPClient(
                    eventLoopGroupProvider: .singleton,
                    configuration: HTTPClient.Configuration(
                        tlsConfiguration: trust, proxy: .server(host: "127.0.0.1", port: harness.proxyPort)
                    )
                )
                defer { try? client.syncShutdown() }
                let secret = HTTPClientRequest(url: "https://[::1]:\(port)/secret")
                let response = try await client.execute(secret, timeout: .seconds(10))
                let body = try await String(buffer: response.body.collect(upTo: 1 << 20))
                #expect(response.status.code == 200)
                #expect(body.hasPrefix("GET /secret host=[::1]:\(port)"), "\(body)")
                let flow = try #require(harness.engine.store.all.first)
                #expect(flow.request.scheme == "https")
                #expect(flow.request.host == "::1")
                #expect(flow.clientTLS?.isEmpty == false)
            }
        }
    }
}
