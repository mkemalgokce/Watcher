import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CertificatePageTests {
    @Test
    func routesAndFormats() throws {
        let directory = try TemporaryDirectory()
        let authority = try CertificateAuthority(directory: directory.url)
        let page = CertificatePage(authority: authority)
        #expect(page.response(forPath: "/").headers.value(for: "Content-Type") == "text/html; charset=utf-8")
        #expect(page.response(forPath: "/ca.cer").body == authority.certificateDER)
        let pem = page.response(forPath: "/ca.pem?x=1").body
        #expect(String(bytes: pem, encoding: .utf8) == authority.certificatePEM)
        #expect(page.response(forPath: "/nope").status == 404)
        let profile = try #require(
            PropertyListSerialization.propertyList(from: page.mobileConfig(), format: nil) as? [String: Any]
        )
        let content = try #require((profile["PayloadContent"] as? [[String: Any]])?.first)
        #expect(content["PayloadType"] as? String == "com.apple.security.root")
        #expect(content["PayloadContent"] as? Data == authority.certificateDER)
    }

    @Test(arguments: [
        ("watcher.cert", 80, [String](), true),
        ("192.168.1.5", 9090, ["192.168.1.5"], true),
        ("192.168.1.5", 80, ["192.168.1.5"], false),
        ("example.com", 9090, ["192.168.1.5"], false),
    ])
    func isAddressedByItsNameOrALocalAddressOnTheProxyPort(
        host: String,
        port: Int,
        localAddresses: [String],
        isAddressed: Bool
    ) {
        #expect(
            CertificatePage.isAddressed(host: host, port: port, proxyPort: 9090, localAddresses: Set(localAddresses))
                == isAddressed
        )
    }
}
