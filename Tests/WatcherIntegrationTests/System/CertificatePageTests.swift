import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
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

    /// A phone typing the Mac's LAN address and the proxy port reaches the page; the address list is the seam.
    @Test
    func servedOnTheMacsOwnLANAddress() async throws {
        let directory = try TemporaryDirectory()
        let authority = try CertificateAuthority(directory: directory.url)
        let server = ProxyServer(authority: authority, clientApp: { _ in nil }, localAddresses: { ["10.9.8.7"] })
        let port = try await server.start(port: 0)
        let client = RawClient()
        try await client.connect(port: port)
        try await client.send("GET http://10.9.8.7:\(port)/ca.pem HTTP/1.1\r\nHost: 10.9.8.7:\(port)\r\n\r\n")
        let reply = await client.received(containing: "END CERTIFICATE")
        await client.close()
        try await server.stop()
        #expect(reply.hasPrefix("HTTP/1.1 200"))
        #expect(reply.contains(authority.certificatePEM))
        #expect(server.store.all.isEmpty)
    }
}
