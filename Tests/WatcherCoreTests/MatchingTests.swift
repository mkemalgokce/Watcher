@testable import WatcherCore
import XCTest

final class MatchingTests: XCTestCase {
    private func request(_ method: String = "GET", host: String = "api.example.com", path: String = "/v1/users", body: String = "") -> RequestRecord {
        RequestRecord(method: method, scheme: "https", host: host, port: 443, path: path, body: Data(body.utf8))
    }

    func testWildcardAcceptsSchemeLessPatternsQuestionMarkAndSubpaths() {
        XCTAssertTrue(MatchingRule(pattern: "api.example.com/v1/*").compile().matches(request()))
        XCTAssertTrue(MatchingRule(pattern: "api.example.com/v1/user?").compile().matches(request(path: "/v1/users")))
        XCTAssertFalse(MatchingRule(pattern: "api.example.com/v2/*").compile().matches(request()))
        XCTAssertTrue(MatchingRule(pattern: "https://api.example.com/v1", includeSubpaths: true).compile().matches(request()))
    }

    func testRegexMethodAndGraphQL() {
        XCTAssertTrue(MatchingRule(pattern: #"example\.com/v\d/users$"#, mode: .regex).compile().matches(request()))
        XCTAssertFalse(MatchingRule(pattern: "*", methods: ["POST"]).compile().matches(request()))
        let graphQL = MatchingRule(pattern: "*", graphQLQueryName: "GetUser").compile()
        XCTAssertTrue(graphQL.matches(request("POST", body: #"{"operationName":"GetUser"}"#)))
        XCTAssertFalse(graphQL.matches(request("POST", body: #"{"operationName":"Other"}"#)))
    }

    func testHostFilterExcludeWins() {
        let filter = HostFilter(include: ["*.example.com"], exclude: ["secure.example.com"])
        XCTAssertTrue(filter.allows("api.example.com"))
        XCTAssertFalse(filter.allows("secure.example.com"))
    }

    func testMapLocalDirectoryRefusesTraversal() {
        let dir = FileManager.default.temporaryDirectory.path
        let escape = RequestRecord(method: "GET", scheme: "https", host: "a.com", port: 443, path: "/static/../../etc/passwd")
        XCTAssertNil(MapLocalTool.resolve(request: escape, pattern: "a.com/static/*", directory: dir))
        let encoded = RequestRecord(method: "GET", scheme: "https", host: "a.com", port: 443, path: "/static/%2e%2e/%2e%2e/etc/passwd")
        XCTAssertNil(MapLocalTool.resolve(request: encoded, pattern: "a.com/static/*", directory: dir))
        let fine = RequestRecord(method: "GET", scheme: "https", host: "a.com", port: 443, path: "/static/app.js?v=1")
        XCTAssertEqual(MapLocalTool.resolve(request: fine, pattern: "a.com/static/*", directory: dir)?.lastPathComponent, "app.js")
    }
}
