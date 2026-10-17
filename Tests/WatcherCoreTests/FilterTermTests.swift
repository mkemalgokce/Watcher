@testable import WatcherCore
import WatcherTestSupport
import XCTest

/// Scoped text conditions from the search field's tokens: each must match, alongside the free text.
final class FilterTermTests: XCTestCase {
    private func flow(
        host: String = "api.example.com",
        path: String = "/login",
        header: Header? = nil,
        body: String = ""
    ) -> Flow {
        .fixture(
            request: .fixture(method: "POST", host: host, path: path, headers: header.map { [$0] } ?? []),
            response: .fixture(body: Data(body.utf8))
        )
    }

    func testEveryTermMustMatch() {
        var filter = FlowFilter()
        filter.terms = [.init(scope: .url, text: "login"), .init(scope: .body, text: "token")]
        XCTAssertTrue(filter.isActive)
        XCTAssertTrue(filter.matches(flow(body: "{\"token\":1}")))
        XCTAssertFalse(filter.matches(flow(body: "{}")), "the body term fails")
        XCTAssertFalse(filter.matches(flow(path: "/logout", body: "token")), "the URL term fails")
    }

    func testTermsCombineWithTheFreeText() {
        var filter = FlowFilter()
        filter.terms = [.init(scope: .header, text: "Bearer")]
        filter.text = "login"
        XCTAssertTrue(filter.matches(flow(header: Header("Authorization", "Bearer x"))))
        XCTAssertFalse(filter.matches(flow(path: "/other", header: Header("Authorization", "Bearer x"))))
    }

    func testHostScopeLooksOnlyAtTheHost() {
        var filter = FlowFilter()
        filter.terms = [.init(scope: .host, text: "example")]
        XCTAssertTrue(filter.matches(flow(host: "API.Example.com")))
        XCTAssertFalse(filter.matches(flow(host: "other.net", path: "/example")), "a path is not the host")
    }

    func testAnEmptyTermIsIgnoredAndResetClearsTerms() {
        var filter = FlowFilter()
        filter.terms = [.init(scope: .body, text: "")]
        XCTAssertTrue(filter.matches(flow()))
        filter.terms = [.init(scope: .body, text: "x")]
        filter.reset()
        XCTAssertTrue(filter.terms.isEmpty)
        XCTAssertFalse(filter.isActive)
    }

    func testTurkishLocaleStillMatchesASCIIInTerms() {
        var filter = FlowFilter(locale: Locale(identifier: "tr_TR"))
        filter.terms = [.init(scope: .header, text: "id")]
        XCTAssertTrue(filter.matches(flow(header: Header("X-Request-ID", "1"))))
    }
}
