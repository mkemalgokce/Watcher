import Testing
@testable import WatcherCore
@testable import WatcherUI

private let both = "Not marked Secure · Readable by scripts (no HttpOnly)"

@Suite(.tags(.unit))
struct KeyValueRowTests {
    private func cookie(
        _ source: CookieEntry.Source, _ attributes: [String] = [], value: String = "v"
    ) -> CookieEntry {
        CookieEntry(source: source, name: "sid", value: value, attributes: attributes)
    }

    @Test(arguments: [
        (CookieEntry.Source.response, [String](), true, Optional(both)),
        (.response, ["HttpOnly"], true, "Not marked Secure"),
        (.response, ["Secure"], true, "Readable by scripts (no HttpOnly)"),
        (.response, ["secure", "httponly"], true, nil),
        (.response, [], false, "Readable by scripts (no HttpOnly)"),
        (.response, ["HttpOnly"], false, nil),
        (.request, [], true, nil),
        (.request, [], false, nil),
    ])
    func onlyResponseCookiesWarnAndSecureOnlyMattersOverHTTPS(
        source: CookieEntry.Source, attributes: [String], https: Bool, warning: String?
    ) {
        let rows = KeyValueRow.cookies([cookie(source, attributes)], secureConnection: https)
        #expect(rows.first?.warning == warning)
    }

    @Test
    func aCookiesAttributesFollowItsValue() {
        let rows = KeyValueRow.cookies([cookie(.response, ["Path=/", "HttpOnly"])], secureConnection: false)
        #expect(rows.first?.value == "v  ·  Path=/; HttpOnly")
        #expect(KeyValueRow.cookies([cookie(.request)], secureConnection: true).first?.value == "v")
    }

    @Test
    func aCookieSaysWhoSentIt() {
        let rows = KeyValueRow.cookies([cookie(.request), cookie(.response)], secureConnection: true)
        #expect(rows.map(\.symbolHelp) == ["Sent by the client", "Set by the server"])
        #expect(rows.map(\.symbol) == ["arrow.up.circle", "arrow.down.circle"])
    }

    @Test(arguments: [
        (FormField.Source.query, "questionmark.circle", "Query parameter"),
        (.form, "list.bullet.rectangle", "Form field"),
        (.multipart, "paperclip", "Multipart part"),
    ])
    func eachFieldShowsWhereItCameFrom(source: FormField.Source, symbol: String, help: String) {
        let rows = KeyValueRow.fields([FormField(source: source, name: "n", value: "v", filename: nil)])
        #expect(rows.first?.symbol == symbol)
        #expect(rows.first?.symbolHelp == help)
    }

    @Test
    func aFieldCarriesItsFileOnlyWhenItHasAFilename() {
        let plain = FormField(source: .multipart, name: "t", value: "v", filename: nil)
        let upload = FormField(source: .multipart, name: "f", value: "x", filename: "a.png")
        let rows = KeyValueRow.fields([plain, upload])
        #expect(rows.map { $0.file != nil } == [false, true])
    }

    @Test
    func rowsKeepTheirIdentityWhenRebuilt() {
        let headers = [Header("A", "1"), Header("A", "1")]
        let first = KeyValueRow.headers(headers).map(\.id)
        #expect(first == KeyValueRow.headers(headers).map(\.id))
        #expect(Set(first).count == 2, "equal headers are still two rows")
    }
}

@Suite(.tags(.unit))
struct KeyValueFilterTests {
    private func rows(_ count: Int) -> [KeyValueRow] {
        KeyValueRow.headers((0 ..< count).map { Header("Name-\($0)", "Value \($0)") })
    }

    @Test(arguments: [(0, false), (8, false), (9, true)])
    func theFilterIsOfferedOnlyAboveEightRows(count: Int, offered: Bool) {
        #expect(KeyValueFilter.isOffered(forRowCount: count) == offered)
    }

    @Test(arguments: [("name-3", 1), ("VALUE 4", 1), ("name-", 12), ("", 12), ("nothing", 0)])
    func theFilterMatchesNamesAndValuesIgnoringCase(filter: String, count: Int) {
        #expect(KeyValueFilter.apply(filter, to: rows(12)).count == count)
    }

    @Test
    func aFilterLeftOverFromALongListIsIgnoredOnceTheListIsShort() {
        #expect(KeyValueFilter.apply("name-3", to: rows(8)).count == 8)
    }
}
