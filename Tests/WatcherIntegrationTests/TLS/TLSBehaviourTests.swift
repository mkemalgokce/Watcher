import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(
    .timeLimit(.minutes(1)),
    .tags(.integration, .network, .externalTool),
    .enabled(if: ExternalTool.python3.isAvailable, "needs python3")
)
struct TLSBehaviourTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory(prefix: "watcher-keylog")
    }

    @Test
    func clientTLSVersionAndProtocolAreRecordedOnDecryptedConnections() async throws {
        try await withHarness { harness in
            _ = try runPython(pythonTLSViaProxy(port: harness.proxyPort, host: "upstream.test", verify: false) + """

            t.sendall(b"GET /tls HTTP/1.1\\r\\nHost: upstream.test\\r\\nConnection: close\\r\\n\\r\\n")
            t.settimeout(10)
            try: t.recv(4096)
            except Exception: pass
            """)
            _ = await eventually(poll: .milliseconds(50)) {
                harness.engine.store.all.first?.clientTLS != nil
            }
            let flow = try #require(harness.engine.store.all.first)
            #expect(flow.request.path == "/tls")
            let tls = try #require(flow.clientTLS)
            #expect(tls.hasPrefix("TLS 1.") && tls.hasSuffix("http/1.1"), "\(tls)")
        }
    }

    @Test
    func http2IsOfferedOnlyWhenPreferred() async throws {
        try await withHarness { harness in
            func negotiated() throws -> String {
                let script = pythonTLSViaProxy(
                    port: harness.proxyPort,
                    host: "alpn.test",
                    verify: false,
                    alpn: ["h2", "http/1.1"]
                ) + "\nprint(t.selected_alpn_protocol() if t else 'failed')"
                return try runPython(script).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            #expect(try negotiated() == "h2")
            try await harness.reconfigure { $0.preferHTTP2 = false }
            #expect(try negotiated() == "http/1.1")
        }
    }

    @Test
    func aClientThatRejectsTheCertificateGetsItsHostExcludedWhenAutoIgnoreIsOn() async throws {
        try await withHarness(configure: { $0.autoIgnoreSSLPinning = true }) { harness in
            let output = try runPython(
                pythonTLSViaProxy(port: harness.proxyPort, host: "pinned.test", verify: true)
                    + "\nprint('rejected' if err else 'accepted')"
            )
            #expect(output.contains("rejected"), "\(output)")
            _ = await eventually(timeout: 3, poll: .milliseconds(50)) {
                harness.engine.settings.value.sslProxying.exclude.contains("pinned.test")
            }
            #expect(harness.engine.settings.value.sslProxying.exclude == ["pinned.test"])
        }
    }

    @Test
    func aRejectedHandshakeIsIgnoredWhenAutoIgnoreIsOff() async throws {
        try await withHarness { harness in
            let logged = LockedBox<[String]>([])
            harness.engine.onLog = { line in logged.mutate { $0.append(line) } }
            _ = try runPython(
                pythonTLSViaProxy(port: harness.proxyPort, host: "pinned.test", verify: true) + "\nprint(1)"
            )
            let abandoned = await eventually { logged.value.contains("pinned.test abandoned the TLS handshake") }
            #expect(abandoned, "\(logged.value)")
            #expect(harness.engine.settings.value.sslProxying.exclude.isEmpty)
        }
    }

    @Test
    func theTLSKeyLogReceivesSessionSecretsInANonPublicFile() async throws {
        let log = directory.appending("keylog.txt")
        try await withHarness(configure: { $0.tlsKeyLogFile = log.path }) { harness in
            _ = try runPython(
                pythonTLSViaProxy(port: harness.proxyPort, host: "keys.test", verify: false)
                    + "\nprint(t.version() if t else 'failed')"
            )
            _ = await eventually(poll: .milliseconds(50)) {
                (try? String(contentsOf: log, encoding: .utf8))?.isEmpty == false
            }
            let content = try String(contentsOf: log, encoding: .utf8)
            #expect(content.contains("CLIENT_RANDOM") || content.contains("TRAFFIC_SECRET"), "\(content)")
            let permissions = try FileManager.default.attributesOfItem(atPath: log.path)[.posixPermissions] as? Int
            #expect(permissions == 0o600)
        }
    }
}
