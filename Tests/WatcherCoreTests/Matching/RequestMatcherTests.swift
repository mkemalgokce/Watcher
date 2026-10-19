import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RequestMatcherTests {
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

    @Test
    func anInvalidRegexMatchesNothingAndDoesNotCrash() {
        #expect(!MatchingRule(pattern: "([unclosed", mode: .regex).compile().matches(request()))
    }

    @Test(arguments: [MatchingRule.Mode.wildcard, .regex])
    func anEmptyPatternMatchesEveryURL(mode: MatchingRule.Mode) {
        #expect(MatchingRule(pattern: "", mode: mode).compile().matches(request()))
    }

    @Test(arguments: [("users", true), ("USERS", true), ("^https", true), ("^example", false), ("v1/us$", false)])
    func aRegexIsUnanchoredAndIgnoresCase(pattern: String, matches: Bool) {
        #expect(MatchingRule(pattern: pattern, mode: .regex).compile().matches(request()) == matches)
    }

    @Test(arguments: [
        ("api.test:8443/*", 8443, true), ("api.test:8443/*", 443, false), ("api.test/*", 8443, false),
        ("api.test:443/v1/users", 443, true),
    ] as [(String, Int, Bool)])
    func aPatternMayNameThePort(pattern: String, port: Int, matches: Bool) {
        let request = RequestRecord.fixture(host: "api.test", port: port, path: "/v1/users")
        #expect(MatchingRule(pattern: pattern).compile().matches(request) == matches)
    }

    @Test(arguments: [("get", "GET", true), ("GET", "get", true), ("POST", "GET", false)])
    func methodsAreComparedIgnoringCase(rule: String, method: String, matches: Bool) {
        #expect(MatchingRule(pattern: "*", methods: [rule]).compile().matches(request(method)) == matches)
    }

    @Test(arguments: [
        (nil as String?, "Google Chrome", true), ("", "Google Chrome", true),
        ("Google Chrome*", "Google Chrome Helper", true),
        ("Google Chrome*", "Safari", false), ("Safari", nil, false), (nil, nil, true), ("", nil, true),
    ] as [(String?, String?, Bool)])
    func theAppFilterNeedsAProgramOnlyWhenItNamesOne(pattern: String?, app: String?, matches: Bool) {
        let request = RequestRecord.fixture(host: "api.test", path: "/", clientApp: app)
        #expect(MatchingRule(pattern: "*", app: pattern).compile().matches(request) == matches)
    }

    @Test(arguments: [
        ("Google Chrome", "Google Chrome Helper", true),
        ("Google Chrome Helper*", "Google Chrome Helper (Renderer)", true),
        ("Google Chrome", "curl", true), ("Safari", "Google Chrome Helper", false),
        ("curl", "Google Chrome Helper", false),
    ])
    func theAppFilterMatchesTheOwnerNameOrTheRawProcessName(pattern: String, process: String, matches: Bool) {
        var request = RequestRecord.fixture(host: "api.test", path: "/", clientApp: "Google Chrome")
        request.clientProcess = process
        #expect(MatchingRule(pattern: "*", app: pattern).compile().matches(request) == matches)
    }

    @Test(arguments: ["not json", "[]", #"{"query":"{ me }"}"#, ""])
    func aGraphQLRuleRejectsABodyWithoutAnOperationName(body: String) {
        let rule = MatchingRule(pattern: "*", graphQLQueryName: "GetUser").compile()
        #expect(!rule.matches(request("POST", body: body)))
    }

    @Test(arguments: [
        ("https://api.example.com/v1", true), ("https://api.example.com/v1/*", true), ("https://x.test", false),
    ])
    func subpathsAreIncludedUnlessThePatternAlreadyEndsInAStar(pattern: String, matches: Bool) {
        #expect(MatchingRule(pattern: pattern, includeSubpaths: true).compile().matches(request()) == matches)
    }

    @Test(arguments: [(nil as String?, false), ("", false), ("GetUser", true)])
    func onlyAGraphQLRuleReadsTheBody(name: String?, reads: Bool) {
        #expect(MatchingRule(pattern: "*", graphQLQueryName: name).compile().readsBody == reads)
    }
}
