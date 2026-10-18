import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProxyServerTests {
    /// A client that refuses Watcher's certificate, with auto-ignore on and off.
    @Suite(
        .timeLimit(.minutes(1)),
        .tags(.integration, .network, .externalTool),
        .enabled(if: ExternalTool.python3.isAvailable, "needs python3")
    )
    struct Pinning {
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
    }
}
