import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(
    .timeLimit(.minutes(1)),
    .tags(.integration, .network, .externalTool),
    .enabled(if: ExternalTool.python3.isAvailable, "needs python3")
)
struct KeyLogFileTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory(prefix: "watcher-keylog")
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
