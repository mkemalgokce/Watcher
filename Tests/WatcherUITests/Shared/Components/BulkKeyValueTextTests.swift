import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@Suite(.tags(.unit))
struct BulkKeyValueTextTests {
    private func pairs(_ rows: [KeyValue]) -> [[String]] {
        rows.map { [$0.name, $0.value, $0.isEnabled ? "on" : "off"] }
    }

    @Test(arguments: [
        ("A: b", ["A", "b", "on"]),
        ("a=b", ["a", "b", "on"]),
        ("a=http://x", ["a", "http://x", "on"]),
        ("next=https://a.com/?x=1", ["next", "https://a.com/?x=1", "on"]),
        ("Referer: http://x", ["Referer", "http://x", "on"]),
        ("Cookie: a=b; c=d", ["Cookie", "a=b; c=d", "on"]),
        ("// Disabled: 1", ["Disabled", "1", "off"]),
        ("//Disabled=1", ["Disabled", "1", "off"]),
        ("  padded  :  value  ", ["padded", "value", "on"]),
        ("lonely", ["lonely", "", "on"]),
        ("empty:", ["empty", "", "on"]),
    ])
    func aLineBecomesARow(line: String, expected: [String]) {
        #expect(pairs(BulkKeyValueText.parse(line)) == [expected])
    }

    @Test(arguments: ["", "//", "// ", "   ", "\n\n"])
    func blankLinesAndBareCommentMarksMakeNoRow(text: String) {
        #expect(BulkKeyValueText.parse(text).isEmpty)
    }

    @Test
    func lineOrderIsKept() {
        #expect(BulkKeyValueText.parse("b: 1\n\na: 2\n// c: 3").map(\.name) == ["b", "a", "c"])
    }

    @Test
    func textRowsRoundTripThroughTheirText() {
        let rows = [KeyValue("A", "1"), KeyValue("B", "x: y", isEnabled: false), KeyValue("C", "")]
        let text = BulkKeyValueText.text(for: rows)
        #expect(pairs(BulkKeyValueText.parse(text)) == pairs(rows))
    }

    @Test
    func fileRowsHaveNoTextAndKeepTheirPlaceWhenTheTextIsApplied() {
        var file = KeyValue("photo", "")
        file.file = .init(filename: "a.png", contentType: "image/png", data: Data([1]))
        let first = KeyValue("a", "1"), last = KeyValue("z", "2")
        let rows = [first, file, last]
        #expect(BulkKeyValueText.text(for: rows) == "a: 1\nz: 2")

        let edited = BulkKeyValueText.apply("a: 1\nz: 3\nnew: 4", to: rows)

        #expect(edited.map(\.name) == ["a", "photo", "z", "new"])
        #expect(edited.map(\.id).prefix(3) == [first.id, file.id, last.id])
        #expect(edited[2].value == "3")
        #expect(edited[1].file != nil)
    }

    @Test
    func deletedLinesDropTheirRows() {
        let rows = [KeyValue("a", "1"), KeyValue("b", "2")]
        #expect(BulkKeyValueText.apply("a: 1", to: rows).map(\.name) == ["a"])
        #expect(BulkKeyValueText.apply("", to: rows).isEmpty)
    }

    @Test(arguments: [
        ("a:b=c", ["a:b", "c", "on"]),
        ("next=https://a.com", ["next", "https://a.com", "on"]),
        ("// k:1=2", ["k:1", "2", "off"]),
        ("lonely:", ["lonely:", "", "on"]),
        ("  pad = v ", ["pad", "v", "on"]),
    ])
    func aFormLineSplitsOnTheFirstEqualsSignOnly(line: String, expected: [String]) {
        #expect(pairs(BulkKeyValueText.parse(line, style: .form)) == [expected])
    }

    @Test
    func formRowsAreWrittenAsNameEqualsValueAndRoundTripWithColonsInNames() {
        let rows = [KeyValue("a:b", "x: y"), KeyValue("c", "1", isEnabled: false)]
        let text = BulkKeyValueText.text(for: rows, style: .form)
        #expect(text == "a:b=x: y\n// c=1")
        #expect(pairs(BulkKeyValueText.parse(text, style: .form)) == pairs(rows))
    }

    @Test
    func applyingFormTextKeepsRowIdentity() {
        let row = KeyValue("a:b", "1")
        let edited = BulkKeyValueText.apply("a:b=2", to: [row], style: .form)
        #expect(edited.map(\.id) == [row.id])
        #expect(edited[0].value == "2")
    }
}
