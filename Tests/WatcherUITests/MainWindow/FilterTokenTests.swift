import Testing
@testable import WatcherCore
@testable import WatcherUI

/// The search field's tokens: what they filter, how they read, and what is offered while typing.
struct FilterTokenTests {
    @Test
    func tokensRoundTripThroughTheFilter() {
        let tokens: [FilterToken] = [
            .method("POST"), .status(4), .status(0), .kind(.json), .term(.init(scope: .body, text: "token")),
        ]
        var filter = FlowFilter()
        FilterToken.apply(tokens, to: &filter)
        #expect(filter.methods == ["POST"])
        #expect(filter.statusClasses == [4, 0])
        #expect(filter.contentKinds == [.json])
        #expect(filter.terms == [.init(scope: .body, text: "token")])
        #expect(Set(FilterToken.tokens(in: filter)) == Set(tokens))

        FilterToken.apply([], to: &filter)
        #expect(!filter.isActive, "removing every token clears what they set")
    }

    @Test
    func applyingTokensKeepsTheFreeTextAndSidebarSelection() {
        var filter = FlowFilter()
        filter.text = "login"; filter.host = "example.com"; filter.errorsOnly = true
        FilterToken.apply([.method("GET")], to: &filter)
        #expect(filter.text == "login")
        #expect(filter.host == "example.com")
        #expect(filter.errorsOnly)
    }

    @Test
    func titlesReadAsPlainConditions() {
        #expect(FilterToken.status(4).title == "4xx")
        #expect(FilterToken.status(0).title == "Failed")
        #expect(FilterToken.term(.init(scope: .header, text: "Bearer")).title == "Header contains “Bearer”")
        #expect(FilterToken.term(.init(scope: .all, text: "x")).title == "Anywhere contains “x”")
        #expect(FilterToken.term(.init(scope: .host, text: "api.example.com")).title == "Host: api.example.com")
    }

    @Test
    func anEmptyFieldOffersTheQuickFilters() {
        let offered = FilterToken.suggestions(for: "", hosts: ["example.com"], excluding: [.status(2)])
        #expect(offered.contains(.status(4)))
        #expect(offered.contains(.status(0)), "Failed is offered")
        #expect(offered.contains(.method("POST")))
        #expect(offered.contains(.kind(.json)))
        #expect(!offered.contains(.status(2)), "a token already in the field is not offered again")
        #expect(!offered.contains {
            if case .term = $0 {
                true
            } else {
                false
            }
        }, "no text, no text conditions")
    }

    @Test
    func typingOffersWhereToLookAndMatchingQuickFilters() {
        let hosts = ["api.example.com", "posts.dev", "other.net"]
        let offered = FilterToken.suggestions(for: "po", hosts: hosts, excluding: [])
        #expect(offered.first == .method("POST"), "an exact kind of filter comes first")
        #expect(offered.contains(.term(.init(scope: .host, text: "posts.dev"))))
        #expect(!offered.contains(.term(.init(scope: .host, text: "other.net"))))
        for scope in [FlowFilter.Scope.url, .header, .body, .all] {
            #expect(offered.contains(.term(.init(scope: scope, text: "po"))), "\(scope)")
        }
    }

    /// A blank field counts as empty, so it offers what an empty one does first.
    @Test(arguments: [
        ("4xx", FilterToken.status(4)),
        ("5", .status(5)),
        ("fail", .status(0)),
        ("json", .kind(.json)),
        ("  ", .status(2)),
    ])
    func statusAndTypeAreRecognisedFromWhatIsTyped(typed: String, expected: FilterToken) {
        #expect(FilterToken.suggestions(for: typed, hosts: [], excluding: []).first == expected)
    }

    @Test
    func hostSuggestionsAreCapped() {
        let hosts = (1 ... 20).map { "s\($0).example.com" }
        let offered = FilterToken.suggestions(for: "example", hosts: hosts, excluding: [])
        #expect(offered.filter {
            if case let .term(term) = $0 {
                term.scope == .host
            } else {
                false
            }
        }.count == 5)
    }
}
