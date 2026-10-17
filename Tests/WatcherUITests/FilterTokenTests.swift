@testable import WatcherCore
@testable import WatcherUI
import XCTest

/// The search field's tokens: what they filter, how they read, and what is offered while typing.
final class FilterTokenTests: XCTestCase {
    func testTokensRoundTripThroughTheFilter() {
        let tokens: [FilterToken] = [
            .method("POST"), .status(4), .status(0), .kind(.json), .term(.init(scope: .body, text: "token")),
        ]
        var filter = FlowFilter()
        FilterToken.apply(tokens, to: &filter)
        XCTAssertEqual(filter.methods, ["POST"])
        XCTAssertEqual(filter.statusClasses, [4, 0])
        XCTAssertEqual(filter.contentKinds, [.json])
        XCTAssertEqual(filter.terms, [.init(scope: .body, text: "token")])
        XCTAssertEqual(Set(FilterToken.tokens(in: filter)), Set(tokens))

        FilterToken.apply([], to: &filter)
        XCTAssertFalse(filter.isActive, "removing every token clears what they set")
    }

    func testApplyingTokensKeepsTheFreeTextAndSidebarSelection() {
        var filter = FlowFilter()
        filter.text = "login"; filter.host = "example.com"; filter.errorsOnly = true
        FilterToken.apply([.method("GET")], to: &filter)
        XCTAssertEqual(filter.text, "login")
        XCTAssertEqual(filter.host, "example.com")
        XCTAssertTrue(filter.errorsOnly)
    }

    func testTitlesReadAsPlainConditions() {
        XCTAssertEqual(FilterToken.status(4).title, "4xx")
        XCTAssertEqual(FilterToken.status(0).title, "Failed")
        XCTAssertEqual(FilterToken.term(.init(scope: .header, text: "Bearer")).title, "Header contains “Bearer”")
        XCTAssertEqual(FilterToken.term(.init(scope: .all, text: "x")).title, "Anywhere contains “x”")
        XCTAssertEqual(FilterToken.term(.init(scope: .host, text: "api.example.com")).title, "Host: api.example.com")
    }

    func testAnEmptyFieldOffersTheQuickFilters() {
        let offered = FilterToken.suggestions(for: "", hosts: ["example.com"], excluding: [.status(2)])
        XCTAssertTrue(offered.contains(.status(4)))
        XCTAssertTrue(offered.contains(.status(0)), "Failed is offered")
        XCTAssertTrue(offered.contains(.method("POST")))
        XCTAssertTrue(offered.contains(.kind(.json)))
        XCTAssertFalse(offered.contains(.status(2)), "a token already in the field is not offered again")
        XCTAssertFalse(offered.contains {
            if case .term = $0 {
                true
            } else {
                false
            }
        }, "no text, no text conditions")
    }

    func testTypingOffersWhereToLookAndMatchingQuickFilters() {
        let hosts = ["api.example.com", "posts.dev", "other.net"]
        let offered = FilterToken.suggestions(for: "po", hosts: hosts, excluding: [])
        XCTAssertEqual(offered.first, .method("POST"), "an exact kind of filter comes first")
        XCTAssertTrue(offered.contains(.term(.init(scope: .host, text: "posts.dev"))))
        XCTAssertFalse(offered.contains(.term(.init(scope: .host, text: "other.net"))))
        for scope in [FlowFilter.Scope.url, .header, .body, .all] {
            XCTAssertTrue(offered.contains(.term(.init(scope: scope, text: "po"))), "\(scope)")
        }
    }

    func testStatusAndTypeAreRecognisedFromWhatIsTyped() {
        XCTAssertEqual(FilterToken.suggestions(for: "4xx", hosts: [], excluding: []).first, .status(4))
        XCTAssertEqual(FilterToken.suggestions(for: "5", hosts: [], excluding: []).first, .status(5))
        XCTAssertEqual(FilterToken.suggestions(for: "fail", hosts: [], excluding: []).first, .status(0))
        XCTAssertEqual(FilterToken.suggestions(for: "json", hosts: [], excluding: []).first, .kind(.json))
        let blank = FilterToken.suggestions(for: "  ", hosts: [], excluding: [])
        XCTAssertEqual(blank.first, .status(2), "blank counts as empty")
    }

    func testHostSuggestionsAreCapped() {
        let hosts = (1 ... 20).map { "s\($0).example.com" }
        let offered = FilterToken.suggestions(for: "example", hosts: hosts, excluding: [])
        XCTAssertEqual(offered.filter {
            if case let .term(term) = $0 {
                term.scope == .host
            } else {
                false
            }
        }.count, 5)
    }
}
