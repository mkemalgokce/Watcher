import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RedirectHopTests {
    private static let credentials = ["Authorization", "Cookie", "Proxy-Authorization"]
    private static let headers = credentials.map { Header($0, "secret") } + [
        Header("Host", "a.test"), Header("Content-Type", "text/plain"), Header("Content-Length", "4"),
        Header("X-Keep", "yes"),
    ]

    private func hop(
        _ status: Int,
        to location: String?,
        method: String = "GET",
        scheme: String = "https",
        port: Int = 443
    ) -> RequestRecord? {
        let current = RequestRecord.fixture(
            method: method, scheme: scheme, host: "a.test", port: port, path: "/start",
            headers: Self.headers, body: Data("body".utf8)
        )
        let location = location.map { [Header("Location", $0)] } ?? []
        return RedirectHop.next(after: .fixture(status: status, headers: location), from: current)
    }

    private func names(_ record: RequestRecord) -> Set<String> {
        Set(record.headers.map { $0.name.lowercased() })
    }

    @Test(arguments: [200, 204, 300, 304, 304 + 100, 404, 500])
    func onlyRedirectStatusesAreFollowed(status: Int) {
        #expect(hop(status, to: "/next") == nil)
    }

    @Test(arguments: [nil, "", "mailto:x@y.test", "http://"] as [String?])
    func aMissingOrUnusableLocationEndsTheChain(location: String?) {
        #expect(hop(302, to: location) == nil)
    }

    @Test(arguments: [
        ("/next", "a.test", "/next", 443), ("next", "a.test", "/next", 443),
        ("https://b.test/x?q=1", "b.test", "/x?q=1", 443), ("//b.test/x", "b.test", "/x", 443),
        ("http://b.test", "b.test", "/", 80), ("https://b.test:8443/x", "b.test", "/x", 8443),
    ])
    func theLocationResolvesAgainstTheCurrentURL(location: String, host: String, path: String, port: Int) throws {
        let next = try #require(hop(302, to: location))
        #expect((next.host, next.path, next.port) == (host, path, port))
    }

    @Test(arguments: [
        "https://other.test/x", "//other.test/x", "http://a.test/x", "https://a.test:8443/x", "https://A.TEST:444/",
    ])
    func credentialsDoNotFollowARedirectToAnotherOrigin(location: String) throws {
        let next = try #require(hop(302, to: location))
        #expect(names(next).isDisjoint(with: ["authorization", "cookie", "proxy-authorization"]), "\(location)")
        #expect(names(next).contains("x-keep"))
    }

    @Test(arguments: ["/next", "https://a.test/next", "https://A.TEST/next", "next", "https://a.test:443/next"])
    func credentialsStayOnTheSameOrigin(location: String) throws {
        let next = try #require(hop(302, to: location))
        #expect(names(next).isSuperset(of: ["authorization", "cookie", "proxy-authorization"]), "\(location)")
    }

    @Test
    func theHostHeaderIsLeftForTheNextConnectionToSet() throws {
        #expect(try !names(#require(hop(302, to: "/next"))).contains("host"))
    }

    @Test(arguments: [
        (301, "POST", "GET"), (302, "POST", "GET"), (303, "POST", "GET"), (303, "PUT", "GET"), (303, "GET", "GET"),
        (301, "PUT", "PUT"), (302, "DELETE", "DELETE"), (307, "POST", "POST"), (308, "PUT", "PUT"),
    ])
    func theMethodFollowsTheStatus(status: Int, method: String, expected: String) throws {
        #expect(try #require(hop(status, to: "/next", method: method)).method == expected)
    }

    @Test(arguments: [(303, true), (302, false), (307, false), (308, false)])
    func aMethodChangeDropsTheBodyAndItsContentHeaders(status: Int, changes: Bool) throws {
        let next = try #require(hop(status, to: "/next", method: "POST"))
        #expect(next.body.isEmpty == (changes || status == 302))
        #expect(names(next).contains("content-type") == !(changes || status == 302))
    }

    @Test
    func aPreservedMethodKeepsTheBody() throws {
        let next = try #require(hop(307, to: "/next", method: "POST"))
        #expect(next.body == Data("body".utf8))
        #expect(names(next).isSuperset(of: ["content-type", "content-length"]))
    }
}
