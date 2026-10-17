import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.integration, .network))
struct CertificatePageTests {
    /// A device pointing at the proxy asks for http://watcher.cert/ca.cer and gets the root certificate without any upstream.
    @Test
    func servedThroughTheProxy() async throws {
        try await withHarness { harness in
            let config = URLSessionConfiguration.ephemeral
            config.connectionProxyDictionary = [
                "HTTPEnable": 1,
                "HTTPProxy": "127.0.0.1",
                "HTTPPort": harness.proxyPort,
            ]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(from: #require(URL(string: "http://watcher.cert/ca.cer")))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(data == harness.engine.authority.certificateDER)
            #expect(harness.engine.store.all.isEmpty, "the certificate page is not traffic")
        }
    }
}
