import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct PACEvaluatorTests {
    @Test
    func routesEachHostTheWayTheScriptSays() throws {
        let pac = try PACEvaluator(script: """
        function FindProxyForURL(url, host) {
          if (shExpMatch(host, "*.internal.test")) return "PROXY proxy.local:3128; DIRECT";
          if (dnsDomainIs(host, ".corp")) return "SOCKS socks.local:1080";
          return "DIRECT";
        }
        """)
        #expect(
            pac.route(for: "http://a.internal.test/", host: "a.internal.test") == .http(host: "proxy.local", port: 3128)
        )
        #expect(pac.route(for: "http://wiki.corp/", host: "wiki.corp") == .socks(host: "socks.local", port: 1080))
        #expect(pac.route(for: "http://example.com/", host: "example.com") == .direct)
        #expect(throws: (any Error).self) { try PACEvaluator(script: "var nothing = 1;") }
    }
}
