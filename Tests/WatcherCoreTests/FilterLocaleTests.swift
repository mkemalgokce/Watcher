@testable import WatcherCore
import XCTest

final class FilterLocaleTests: XCTestCase {
    private func flow(header: Header = Header("Accept", "*/*"), body: Data = Data()) -> Flow {
        var request = RequestRecord(method: "GET", scheme: "https", host: "example.com", port: 443, path: "/")
        request.headers = [header]
        var result = Flow(sequence: 1, request: request)
        result.response = ResponseRecord(status: 200, body: body)
        result.state = .completed
        return result
    }

    private func filter(_ text: String, _ scope: FlowFilter.Scope, locale: String) -> FlowFilter {
        var filter = FlowFilter(locale: Locale(identifier: locale))
        filter.text = text
        filter.scope = scope
        return filter
    }

    func testTurkishLocaleStillMatchesASCIIHeaders() {
        let requestID = flow(header: Header("X-Request-ID", "1"))
        let authorization = flow(header: Header("Authorization", "Bearer x"))
        XCTAssertTrue(filter("id", .header, locale: "tr_TR").matches(requestID))
        XCTAssertTrue(filter("AUTHORIZATION", .header, locale: "tr_TR").matches(authorization))
    }

    func testTurkishLocaleStillMatchesTurkishText() {
        XCTAssertTrue(filter("ISTANBUL", .body, locale: "tr_TR").matches(flow(body: Data("şehir: ıstanbul".utf8))))
    }

    func testEnglishLocaleMatchesCaseInsensitively() {
        let requestID = flow(header: Header("X-Request-ID", "1"))
        let authorization = flow(header: Header("Authorization", "Bearer x"))
        XCTAssertTrue(filter("id", .header, locale: "en_US").matches(requestID))
        XCTAssertTrue(filter("AUTHORIZATION", .header, locale: "en_US").matches(authorization))
        XCTAssertFalse(filter("cookie", .header, locale: "en_US").matches(authorization))
    }

    func testNonUTF8BodyNeverMatches() {
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9]) // "café" in Latin-1, invalid UTF-8
        XCTAssertFalse(filter("caf", .body, locale: "tr_TR").matches(flow(body: latin1)))
        XCTAssertFalse(filter("caf", .body, locale: "en_US").matches(flow(body: latin1)))
    }

    func testLocaleIsNotAnActiveFilterAndSurvivesReset() {
        let turkish = Locale(identifier: "tr_TR")
        XCTAssertFalse(FlowFilter(locale: turkish).isActive)
        var filter = FlowFilter(locale: turkish)
        filter.text = "x"
        filter.reset()
        XCTAssertEqual(filter, FlowFilter(locale: turkish))
    }

    func testLargeBodySearchStaysCloseToLocalizedSearch() {
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
        let filtered = time { XCTAssertTrue(missing.apply(to: flows).isEmpty) }
        XCTAssertLessThan(filtered / localized, 4)
    }
}
