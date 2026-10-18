import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension FlowFilterTests {
    @Suite(.tags(.unit), .serialized)
    struct Localization {
        private func flow(header: Header = Header("Accept", "*/*"), body: Data = Data()) -> Flow {
            .fixture(request: .fixture(host: "example.com", headers: [header]), response: .fixture(body: body))
        }

        private func filter(_ text: String, _ scope: FlowFilter.Scope, locale: String) -> FlowFilter {
            var filter = FlowFilter(locale: Locale(identifier: locale))
            filter.text = text
            filter.scope = scope
            return filter
        }

        @Test(arguments: ["tr_TR", "en_US"])
        func asciiHeadersMatchCaseInsensitivelyInEveryLocale(locale: String) {
            let requestID = flow(header: Header("X-Request-ID", "1"))
            let authorization = flow(header: Header("Authorization", "Bearer x"))
            #expect(filter("id", .header, locale: locale).matches(requestID))
            #expect(filter("AUTHORIZATION", .header, locale: locale).matches(authorization))
        }

        @Test
        func turkishLocaleStillMatchesTurkishText() {
            #expect(filter("ISTANBUL", .body, locale: "tr_TR").matches(flow(body: Data("şehir: ıstanbul".utf8))))
        }

        @Test
        func englishLocaleDoesNotMatchAnAbsentHeader() {
            let authorization = flow(header: Header("Authorization", "Bearer x"))
            #expect(!filter("cookie", .header, locale: "en_US").matches(authorization))
        }

        @Test(arguments: ["tr_TR", "en_US"])
        func nonUTF8BodyNeverMatches(locale: String) {
            let latin1 = Data([0x63, 0x61, 0x66, 0xE9]) // "café" in Latin-1, invalid UTF-8
            #expect(!filter("caf", .body, locale: locale).matches(flow(body: latin1)))
        }

        @Test
        func localeIsNotAnActiveFilterAndSurvivesReset() {
            let turkish = Locale(identifier: "tr_TR")
            #expect(!FlowFilter(locale: turkish).isActive)
            var filter = FlowFilter(locale: turkish)
            filter.text = "x"
            filter.reset()
            #expect(filter == FlowFilter(locale: turkish))
        }

        @Test(.tags(.timing))
        func largeBodySearchStaysCloseToLocalizedSearch() {
            let body = String(repeating: "{\"name\":\"value\",\"count\":12345}\n", count: 30000)
            let flows = (0 ..< 5).map { _ in flow(body: Data(body.utf8)) }
            let missing = filter("needle-not-there", .body, locale: "tr_TR")
            func time(_ work: () -> Void) -> TimeInterval {
                let start = Date()
                work()
                return Date().timeIntervalSince(start)
            }
            let localized = time {
                for _ in flows {
                    _ = body.localizedCaseInsensitiveContains("needle-not-there")
                }
            }
            let filtered = time { #expect(missing.apply(to: flows).isEmpty) }
            #expect(filtered / localized < 40)
        }
    }
}
