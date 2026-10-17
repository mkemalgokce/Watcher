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
}
