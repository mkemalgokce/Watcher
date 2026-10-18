import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MapRemoteToolTests {
    @Test
    func hostHeaderFollowsTheDestinationUnlessPreserved() async {
        var rule = MapRemoteRule(matching: MatchingRule(pattern: "*"), destination: .init(host: "new.test"))
        var request = RequestRecord.fixture(host: "old.test", headers: [Header("Host", "old.test")])
        _ = await MapRemoteTool(rules: [rule]).intercept(request: &request)
        #expect(request.headers.value(for: "host") == "new.test")
        rule.preserveHostHeader = true
        var kept = RequestRecord.fixture(host: "old.test", headers: [Header("Host", "old.test")])
        _ = await MapRemoteTool(rules: [rule]).intercept(request: &kept)
        #expect(kept.host == "new.test"); #expect(kept.headers.value(for: "host") == "old.test")
    }

    private func mapped(
        _ destination: MapRemoteRule.Destination,
        from request: RequestRecord,
        pattern: String = "*"
    ) async -> RequestRecord {
        var request = request
        let rule = MapRemoteRule(matching: MatchingRule(pattern: pattern), destination: destination)
        _ = await MapRemoteTool(rules: [rule]).intercept(request: &request)
        return request
    }

    @Test(arguments: [
        (RequestRecord.fixture(scheme: "http", port: 80), "https", nil as Int?, 443),
        (.fixture(scheme: "https", port: 443), "http", nil, 80),
        (.fixture(scheme: "http", port: 80), "https", 8443, 8443),
    ] as [(RequestRecord, String, Int?, Int)])
    func aSchemeChangeTakesTheNewSchemesDefaultPortUnlessOneIsGiven(
        original: RequestRecord,
        scheme: String,
        port: Int?,
        expected: Int
    ) async {
        let request = await mapped(.init(scheme: scheme, port: port), from: original)
        #expect(request.scheme == scheme)
        #expect(request.port == expected)
    }

    @Test
    func aPortOnlyChangesThePort() async {
        let request = await mapped(.init(port: 9000), from: .fixture(path: "/a?b=1"))
        #expect(request.port == 9000 && request.host == "api.example.com" && request.path == "/a?b=1")
    }

    @Test(arguments: [
        (MapRemoteRule.Destination(path: "/new"), "/old?x=1", "/new?x=1"),
        (.init(query: "y=2"), "/old?x=1", "/old?y=2"),
        (.init(query: "y=2"), "/old", "/old?y=2"),
        (.init(path: "/new", query: ""), "/old?x=1", "/new"),
        (.init(query: ""), "/old?x=1", "/old"),
        (.init(path: "/new", query: "z=3"), "/old?x=1", "/new?z=3"),
    ] as [(MapRemoteRule.Destination, String, String)])
    func aPathOrQueryReplacesOnlyItsOwnPart(
        destination: MapRemoteRule.Destination,
        path: String,
        expected: String
    ) async {
        let request = await mapped(destination, from: .fixture(path: path))
        #expect(request.path == expected)
    }

    @Test(arguments: [(8080, "new.test:8080"), (443, "new.test")])
    func theHostHeaderNamesANonDefaultPort(port: Int, header: String) async {
        let original = RequestRecord.fixture(host: "old.test", headers: [Header("Host", "old.test")])
        let request = await mapped(.init(host: "new.test", port: port), from: original)
        #expect(request.headers.value(for: "Host") == header)
    }

    @Test
    func theFirstMatchingRuleWins() async {
        var request = RequestRecord.fixture(host: "old.test", path: "/a")
        let rules = [
            MapRemoteRule(matching: MatchingRule(pattern: "*/nope"), destination: .init(host: "skipped.test")),
            MapRemoteRule(matching: MatchingRule(pattern: "*/a"), destination: .init(host: "first.test")),
            MapRemoteRule(matching: MatchingRule(pattern: "*"), destination: .init(host: "second.test")),
        ]
        _ = await MapRemoteTool(rules: rules).intercept(request: &request)
        #expect(request.host == "first.test")
    }

    @Test
    func aRequestMatchingNoRuleIsLeftAlone() async {
        let original = RequestRecord.fixture(host: "old.test", path: "/a")
        let request = await mapped(.init(host: "new.test"), from: original, pattern: "other.test/*")
        #expect(request == original)
    }
}
