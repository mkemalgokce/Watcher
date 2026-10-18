import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
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

    @Test(arguments: [
        ("DIRECT", PACEvaluator.Route.direct),
        ("", .direct),
        ("  proxy a.test:8080 ; DIRECT", .http(host: "a.test", port: 8080)),
        ("PROXY noport; SOCKS5 s.test:1080", .socks(host: "s.test", port: 1080)),
        ("HTTPS secure.test:443", .http(host: "secure.test", port: 443)),
        ("NONSENSE x:1; PROXY b.test:3128", .http(host: "b.test", port: 3128)),
        ("PROXY b.test:notaport", .direct),
    ])
    func theFirstUsableEntryOfTheAnswerIsTheRoute(answer: String, route: PACEvaluator.Route) throws {
        let pac = try PACEvaluator(script: "function FindProxyForURL(url, host) { return \"\(answer)\"; }")
        #expect(pac.route(for: "http://x.test/", host: "x.test") == route)
    }

    @Test
    func aScriptThatDoesNotRunIsALoadError() {
        #expect(throws: PACEvaluator.LoadError.self) { try PACEvaluator(script: "function FindProxyForURL( {") }
    }

    @Test
    func aScriptThatNeverFinishesLoadingIsALoadError() {
        #expect(throws: PACEvaluator.LoadError.self) {
            try PACEvaluator(script: "for (;;) {} function FindProxyForURL() {}", timeLimit: .milliseconds(50))
        }
    }

    @Test
    func aLookupThatNeverFinishesGoesDirect() throws {
        let pac = try PACEvaluator(
            script: "function FindProxyForURL() { for (;;) {} }",
            timeLimit: .milliseconds(50)
        )
        #expect(pac.route(for: "http://x.test/", host: "x.test") == .direct)
    }

    @Test(arguments: ["ftp://pac.test/proxy.pac", "not a url", ""])
    func onlyHTTPAndFileLocationsAreLoaded(location: String) async {
        let fetched = LockedBox<[URL]>([])
        await #expect(throws: PACEvaluator.LoadError.self) {
            try await PACEvaluator.load(from: location) { url in fetched.mutate { $0.append(url) }; return Data() }
        }
        #expect(fetched.value.isEmpty)
    }

    @Test(arguments: ["http://pac.test/proxy.pac", "https://pac.test/proxy.pac", "file:///etc/proxy.pac"])
    func aScriptIsFetchedFromItsLocationAndEvaluated(location: String) async throws {
        let fetched = LockedBox<[URL]>([])
        let pac = try await PACEvaluator.load(from: location) { url in
            fetched.mutate { $0.append(url) }
            return Data("function FindProxyForURL() { return 'PROXY p.test:1'; }".utf8)
        }
        #expect(fetched.value.map(\.absoluteString) == [location])
        #expect(pac.route(for: "http://x.test/", host: "x.test") == .http(host: "p.test", port: 1))
    }

    @Test
    func aFetchedScriptWithoutTheFunctionIsALoadError() async {
        await #expect(throws: PACEvaluator.LoadError.self) {
            try await PACEvaluator.load(from: "http://pac.test/proxy.pac") { _ in Data("var x = 1;".utf8) }
        }
    }
}
