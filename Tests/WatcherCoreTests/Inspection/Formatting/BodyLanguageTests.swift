import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct BodyLanguageTests {
    @Test(arguments: [
        (String?("application/json; charset=utf-8"), Data(), BodyLanguage.json),
        ("text/html", Data(), .html),
        ("image/png", Data([1]), .binary),
        (nil, Data("  {\"a\":1}".utf8), .json),
        (nil, Data([0xFF, 0xFE, 0x00]), .binary),
    ])
    func detectsLanguageFromContentTypeThenBytes(contentType: String?, data: Data, language: BodyLanguage) {
        #expect(BodyLanguage.detect(contentType: contentType, data: data) == language)
    }

    @Test
    func textWhoseSniffedPrefixEndsInsideACharacterIsStillText() {
        let text = Data((String(repeating: "a", count: 2047) + "é and more").utf8)
        #expect(BodyLanguage.sniff(text) == .plain)
    }

    @Test
    func aShortBodyWithAnInvalidLastByteIsBinary() {
        #expect(BodyLanguage.sniff(Data("abc".utf8) + Data([0xC3])) == .binary)
    }
}
