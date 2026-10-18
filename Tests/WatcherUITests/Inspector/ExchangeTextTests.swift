import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The names, header text and decoded bodies offered by save, copy and Open With.
@Suite(.tags(.unit))
struct ExchangeTextTests {
    private static let json = [Header("Content-Type", "application/json; charset=utf-8")]

    @Test(arguments: [
        ("/v1/users?page=2", json, "users.json"),
        ("/files/report.pdf", json, "report.pdf"),
        ("/", json, "response.json"),
        ("/", [], "response"),
        ("/v1/users", [Header("Content-Type", "x-unknown/thing")], "users"),
    ])
    func suggestedFileNameAddsTheContentTypeExtension(path: String, headers: [Header], expected: String) {
        let flow = Flow.fixture(request: .fixture(host: "h", path: path), response: .fixture(headers: headers))
        #expect(ExchangeText.suggestedFileName(for: flow, side: .response) == expected)
    }

    @Test
    func suggestedFileNameForTheRequestUsesItsOwnContentType() {
        let flow = Flow.fixture(request: .fixture(path: "/", headers: Self.json), response: nil)
        #expect(ExchangeText.suggestedFileName(for: flow, side: .request) == "request.json")
    }

    @Test
    func headerTextIsOneHeaderPerLine() {
        let flow = Flow.fixture(request: .fixture(headers: [Header("A", "1"), Header("B", "2")]))
        #expect(ExchangeText.headerText(of: flow, side: .request) == "A: 1\nB: 2")
        #expect(ExchangeText.headerText(of: Flow.fixture(response: nil), side: .response).isEmpty)
    }

    @Test
    func bodyUndoesTheContentEncoding() {
        let plain = Data(String(repeating: "hello ", count: 50).utf8)
        let flow = Flow.fixture(response: .fixture(headers: [Header("Content-Encoding", "gzip")], body: plain.gzipped))
        #expect(ExchangeText.body(of: flow, side: .response) == plain)
    }

    @Test
    func bodyWithoutAnEncodingIsUnchanged() {
        let flow = Flow.fixture(request: .fixture(body: Data("raw".utf8)))
        #expect(ExchangeText.body(of: flow, side: .request) == Data("raw".utf8))
    }
}
