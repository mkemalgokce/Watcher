import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct HostPortTests {
    @Test(arguments: [
        ("example.com", "example.com", 443), ("example.com:8443", "example.com", 8443),
        ("example.com:", "example.com", 443), ("example.com:abc", "example.com", 443),
        ("example.com:0", "example.com", 443), ("example.com:70000", "example.com", 443),
        ("example.com:-1", "example.com", 443), ("1.2.3.4:80", "1.2.3.4", 80),
        ("[::1]:8443", "::1", 8443), ("[::1]", "::1", 443), ("[::1]:", "::1", 443), ("[::1]:x", "::1", 443),
        ("[fe80::1]:9", "fe80::1", 9), ("::1", "::1", 443),
    ])
    func aTargetSplitsIntoHostAndPort(text: String, host: String, port: Int) throws {
        let parsed = try #require(HostPort(text, defaultPort: 443))
        #expect(parsed == HostPort(host: host, port: port))
    }

    @Test(arguments: ["", ":80", "[]", "[]:80", "[::1", "[:"])
    func aTargetWithoutAHostIsRefused(text: String) {
        #expect(HostPort(text, defaultPort: 80) == nil)
    }

    @Test
    func theDefaultPortIsTheCallers() throws {
        #expect(try #require(HostPort("a.test", defaultPort: 80)).port == 80)
    }
}
