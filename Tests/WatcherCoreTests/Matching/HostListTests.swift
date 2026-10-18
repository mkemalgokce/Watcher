import Testing
@testable import WatcherCore

@Suite(.tags(.unit))
struct HostListTests {
    @Test(arguments: ["", "localhost", "a.test"])
    func anEmptyListMatchesNoHost(host: String) {
        #expect(!HostList([]).matches(host))
    }

    @Test(arguments: [("a.test", true), ("A.TEST", true), ("api.b.test", true), ("b.test", false), ("c.test", false)])
    func aHostMatchesWhenAnyPatternDoes(host: String, matches: Bool) {
        #expect(HostList(["a.test", "*.b.test"]).matches(host) == matches)
    }

    @Test
    func thePatternsAreKeptAsGiven() {
        #expect(HostList(["a.test", "*.b.test"]).patterns == ["a.test", "*.b.test"])
    }
}
