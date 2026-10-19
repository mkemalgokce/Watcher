import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct HTTPEndpointTests {
    @Test(arguments: [
        ("https://Example.com/a/b?x=1", "https", "Example.com", 443, "/a/b?x=1"),
        ("HTTP://example.com", "http", "example.com", 80, "/"),
        ("http://example.com:8080?q=1", "http", "example.com", 8080, "/?q=1"),
        ("https://example.com/a%20b", "https", "example.com", 443, "/a%20b"),
    ])
    func parsesTheEndpointOfAnHTTPURL(address: String, scheme: String, host: String, port: Int, target: String) throws {
        let endpoint = try #require(HTTPEndpoint(address))
        #expect((endpoint.scheme, endpoint.host, endpoint.port, endpoint.target) == (scheme, host, port, target))
    }

    @Test(arguments: [
        "", "example.com", "ftp://example.com", "http://", "https:///path", " http://example.com", "ws://example.com",
    ])
    func rejectsWhatIsNotAnHTTPURLWithAHost(address: String) {
        #expect(HTTPEndpoint(address) == nil)
    }

    @Test
    func anIPv6HostLosesItsBrackets() throws {
        let endpoint = try #require(HTTPEndpoint("http://[::1]:8080/p"))
        #expect((endpoint.host, endpoint.port, endpoint.target) == ("::1", 8080, "/p"))
    }
}
