import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension FlowFilterTests {
    /// Scoped text conditions from the search field's tokens: each must match, alongside the free text.
    @Suite(.tags(.unit))
    struct Term {
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

        @Test
        func everyTermMustMatch() {
            var filter = FlowFilter()
            filter.terms = [.init(scope: .url, text: "login"), .init(scope: .body, text: "token")]
            #expect(filter.isActive)
            #expect(filter.matches(flow(body: "{\"token\":1}")))
            #expect(!filter.matches(flow(body: "{}")), "the body term fails")
            #expect(!filter.matches(flow(path: "/logout", body: "token")), "the URL term fails")
        }

        @Test
        func termsCombineWithTheFreeText() {
            var filter = FlowFilter()
            filter.terms = [.init(scope: .header, text: "Bearer")]
            filter.text = "login"
            #expect(filter.matches(flow(header: Header("Authorization", "Bearer x"))))
            #expect(!filter.matches(flow(path: "/other", header: Header("Authorization", "Bearer x"))))
        }

        @Test
        func hostScopeLooksOnlyAtTheHost() {
            var filter = FlowFilter()
            filter.terms = [.init(scope: .host, text: "example")]
            #expect(filter.matches(flow(host: "API.Example.com")))
            #expect(!filter.matches(flow(host: "other.net", path: "/example")), "a path is not the host")
        }

        @Test
        func anEmptyTermIsIgnoredAndResetClearsTerms() {
            var filter = FlowFilter()
            filter.terms = [.init(scope: .body, text: "")]
            #expect(filter.matches(flow()))
            filter.terms = [.init(scope: .body, text: "x")]
            filter.reset()
            #expect(filter.terms.isEmpty)
            #expect(!filter.isActive)
        }

        @Test
        func turkishLocaleStillMatchesASCIIInTerms() {
            var filter = FlowFilter(locale: Locale(identifier: "tr_TR"))
            filter.terms = [.init(scope: .header, text: "id")]
            #expect(filter.matches(flow(header: Header("X-Request-ID", "1"))))
        }
    }
}
