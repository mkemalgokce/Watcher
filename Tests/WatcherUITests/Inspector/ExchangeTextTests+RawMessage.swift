import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ExchangeTextTests {
    @Suite(.tags(.unit))
    struct RawMessage {
        private func request(headers: [Header] = [], version: String? = nil) -> Flow {
            var flow = Flow.fixture(request: .fixture(host: "a.test", path: "/x?y=1", headers: headers), response: nil)
            flow.upstreamHTTPVersion = version
            return flow
        }

        @Test
        func aRequestSynthesizesAHostHeaderOnlyWhenItHasNone() {
            let bare = ExchangeText.rawMessage(of: request(), side: .request)
            #expect(bare == "GET /x?y=1 HTTP/1.1\nHost: a.test\n\n")
            let named = ExchangeText.rawMessage(of: request(headers: [Header("host", "other.test")]), side: .request)
            #expect(named == "GET /x?y=1 HTTP/1.1\nhost: other.test\n\n")
        }

        @Test(arguments: [("HTTP/2", "HTTP/2"), (nil as String?, "HTTP/1.1")])
        func theRequestLineUsesTheUpstreamVersionOrHTTP11(version: String?, expected: String) {
            let text = ExchangeText.rawMessage(of: request(version: version), side: .request)
            #expect(text.hasPrefix("GET /x?y=1 \(expected)\n"))
        }

        @Test
        func aResponseShowsItsStatusLineHeadersAndBody() {
            let response = ResponseRecord.fixture(status: 404, headers: [Header("X-A", "1")], body: Data("gone".utf8))
            let flow = Flow.fixture(response: response)
            #expect(ExchangeText.rawMessage(of: flow, side: .response) == "HTTP/1.1 404 Not Found\nX-A: 1\n\ngone")
        }

        @Test
        func aMissingResponseIsStatusZeroWithNoBody() {
            let text = ExchangeText.rawMessage(of: request(), side: .response)
            #expect(text.hasPrefix("HTTP/1.1 0 "))
            #expect(text.hasSuffix("\n\n"))
        }

        @Test
        func binaryBodiesAreDescribed() {
            #expect(ExchangeText.bodyText(Data([0xFF, 0xFE, 0x00])) == "<3 bytes of binary data>")
            #expect(ExchangeText.bodyText(Data()) == "")
        }

        @Test(arguments: [0, 1, 2, 3])
        func aLongUTF8BodyIsCutOnACharacterBoundaryNotCalledBinary(offset: Int) {
            // "é" is two bytes, "€" three, "😀" four: the cut falls inside the last character in each case.
            let character = ["é", "€", "😀", "a"][offset]
            let width = character.utf8.count
            let padding = String(repeating: "a", count: ExchangeText.bodyLimit - 1 - (width > 1 ? 0 : -1))
            let body = Data((padding + character + String(repeating: "b", count: 100)).utf8)
            let text = ExchangeText.bodyText(body)
            #expect(!text.hasPrefix("<"), "cut inside \(character)")
            #expect(text.contains("more bytes not shown"))
            #expect(text.hasPrefix(padding))
        }

        @Test
        func aBodyExactlyAtTheLimitIsShownWhole() {
            let body = Data(String(repeating: "a", count: ExchangeText.bodyLimit).utf8)
            #expect(ExchangeText.bodyText(body).count == ExchangeText.bodyLimit)
        }
    }
}
