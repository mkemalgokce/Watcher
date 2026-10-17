import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MatchingRuleTests {
    private func request(_ method: String = "GET", path: String = "/v1/users", body: String = "") -> RequestRecord {
        .fixture(method: method, host: "api.example.com", path: path, body: Data(body.utf8))
    }

    @Test
    func wildcardAcceptsSchemeLessPatternsQuestionMarkAndSubpaths() {
        #expect(MatchingRule(pattern: "api.example.com/v1/*").compile().matches(request()))
        #expect(MatchingRule(pattern: "api.example.com/v1/user?").compile().matches(request(path: "/v1/users")))
        #expect(!MatchingRule(pattern: "api.example.com/v2/*").compile().matches(request()))
        #expect(MatchingRule(pattern: "https://api.example.com/v1", includeSubpaths: true).compile().matches(request()))
    }

    @Test
    func regexMethodAndGraphQLNarrowTheMatch() {
        #expect(MatchingRule(pattern: #"example\.com/v\d/users$"#, mode: .regex).compile().matches(request()))
        #expect(!MatchingRule(pattern: "*", methods: ["POST"]).compile().matches(request()))
        let graphQL = MatchingRule(pattern: "*", graphQLQueryName: "GetUser").compile()
        #expect(graphQL.matches(request("POST", body: #"{"operationName":"GetUser"}"#)))
        #expect(!graphQL.matches(request("POST", body: #"{"operationName":"Other"}"#)))
    }
}
