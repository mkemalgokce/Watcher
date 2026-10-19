import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MatchingRuleURLTests {
    @Test(arguments: [("/", ""), ("/", "/"), ("", "/?q=1"), ("/a.b", "/a.b?q=1")])
    func exactURLMatchesTheRootAndPathWithAnyQuery(path: String, requested: String) {
        let matcher = MatchingRule.exactURL(host: "a.test", path: path).compile()
        #expect(matcher.matches(.fixture(host: "a.test", path: requested)))
        #expect(matcher.matches(.fixture(scheme: "wss", host: "a.test", path: requested)))
    }

    @Test(arguments: [("a.test", "/aXb"), ("a.test", "/a.b/c"), ("evil-a.test", "/a.b"), ("aXtest", "/a.b")])
    func exactURLRejectsOtherPathsAndHosts(host: String, path: String) {
        let matcher = MatchingRule.exactURL(host: "a.test", path: "/a.b").compile()
        #expect(!matcher.matches(.fixture(host: host, path: path)))
    }

    @Test
    func exactURLCarriesTheMethods() {
        let rule = MatchingRule.exactURL(host: "a.test", path: "/", methods: ["POST"])
        #expect(rule.methods == ["POST"])
        #expect(!rule.compile().matches(.fixture(method: "GET", host: "a.test", path: "/")))
    }

    @Test(arguments: [
        ("a.test", false, true), ("cdn.a.test", true, true), ("cdn.a.test", false, false), ("aXtest", true, false)
    ])
    func hostMatchesItselfAndOnlyWhenAskedItsSubdomains(host: String, subdomains: Bool, matches: Bool) {
        let matcher = MatchingRule.host("a.test", subdomains: subdomains).compile()
        #expect(matcher.matches(.fixture(host: host, path: "/x")) == matches)
    }
}
