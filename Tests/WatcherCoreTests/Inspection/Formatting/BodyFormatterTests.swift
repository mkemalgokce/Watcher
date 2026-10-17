import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct BodyFormatterTests {
    @Test
    func formatsByContentType() {
        let json = BodyFormatter.format(Data(#"{"a":1}"#.utf8), contentType: "application/json")
        #expect(json.text == "{\n  \"a\": 1\n}"); #expect(json.language == .json)
        let form = BodyFormatter.format(Data("a=1&b=x+y%21".utf8), contentType: "application/x-www-form-urlencoded")
        #expect(form.text == "a = 1\nb = x y!")
        let xml = BodyFormatter.format(Data("<a><b>1</b></a>".utf8), contentType: "application/xml")
        #expect(xml.text.contains("\n"), "\(xml.text)")
        let bin = BodyFormatter.format(Data([0, 1, 2, 0x41]), contentType: "application/octet-stream")
        #expect(bin.language == .binary); #expect(bin.text.hasPrefix("00000000  00 01 02 41"), "\(bin.text)")
        #expect(BodyFormatter.format(Data(), contentType: nil).text == "")
    }

    @Test
    func formatterNoLongerGivesUpAtTwoMegabytes() {
        let text = "[" + String(repeating: #"{"a":1},"#, count: 400_000) + "1]" // ~3 MB
        let formatted = BodyFormatter.format(Data(text.utf8), contentType: "application/json")
        #expect(formatted.note == nil); #expect(formatted.text.hasPrefix("[\n  {\n    \"a\": 1"))
    }
}
