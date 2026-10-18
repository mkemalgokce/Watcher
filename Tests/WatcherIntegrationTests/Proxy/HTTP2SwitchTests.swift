import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// What the decrypted connection negotiated with the client, seen by a real TLS client.
@Suite(
    .timeLimit(.minutes(1)),
    .tags(.integration, .network, .externalTool),
    .enabled(if: ExternalTool.python3.isAvailable, "needs python3")
)
struct HTTP2SwitchTests {
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
}
