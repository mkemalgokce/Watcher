import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct Base64FinderTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52])

    @Test
    func findsDataURIImageAndJSONValues() throws {
        let note = Data(#"{"alpha":1,"beta":[2]}"#.utf8).base64EncodedString()
        let json = #"{"avatar":"data:image/png;base64,\#(png.base64EncodedString())","note":"\#(note)","id":"abc"}"#
        let found = Base64Finder.find(in: json)
        try #require(found.count == 2)
        #expect(found[0].kind == .image(mime: "image/png")); #expect(found[0].data == png)
        #expect(found[1].kind == .text); #expect(found[1].label == "note")
        #expect(found[1].text?.contains("\"alpha\": 1") == true)
        let utf16 = json as NSString
        #expect(
            utf16.substring(with: found[0].range) == png.base64EncodedString(),
            "ranges point at the encoded text only"
        )
    }

    @Test
    func decodesWholeBodyBase64AndURLSafeAlphabet() {
        let message = "hello world, this is a long enough sentence?>>"
        let url = Data(message.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(Base64Finder.find(in: url).first?.text == message)
        #expect(Base64Finder.find(in: "short").isEmpty)
        #expect(Base64Finder.find(in: "just some ordinary sentence with spaces in it, nothing encoded").isEmpty)
    }

    @Test
    func sniffsBinaryAndImageTypes() {
        let binary = Data((0 ..< 40).map { UInt8($0 * 7 % 251) } + [0, 1, 2])
        #expect(Base64Finder.find(in: binary.base64EncodedString()).first?.kind == .binary)
        #expect(Base64Finder.imageMime(Data([0xFF, 0xD8, 0xFF, 0xE0])) == "image/jpeg")
        #expect(Base64Finder.imageMime(Data("<svg xmlns='x'/>".utf8)) == "image/svg+xml")
        #expect(Base64Finder.imageMime(Data("plain".utf8)) == nil)
    }

    @Test
    func theSameTextGivesTheSameDistinctIds() {
        let text = #"{"a":"aGVsbG8gd29ybGQsIGhlbGxvIHdvcmxk","b":"Zm9vYmFyIGZvb2JhciBmb29iYXIgZm9vYmFy"}"#
        let ids = Base64Finder.find(in: text).map(\.id)
        #expect(ids.count == 2 && Set(ids).count == 2)
        #expect(ids == Base64Finder.find(in: text).map(\.id))
    }
}
