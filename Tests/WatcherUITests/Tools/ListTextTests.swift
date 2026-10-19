import Testing
@testable import WatcherUI

@Suite(.tags(.unit))
struct ListTextTests {
    @Test(arguments: [
        ("a, b ,c", ["a", "b", "c"]),
        ("", []),
        (" , ,", []),
        ("a,,b", ["a", "b"]),
        ("  one  ", ["one"]),
    ])
    func commaSeparatedTextIsTrimmedAndStripsEmptyEntries(text: String, expected: [String]) {
        #expect(ListText.items(text, separator: ",") == expected)
    }

    @Test
    func newlineSeparatedTextKeepsInnerSpaces() {
        #expect(ListText.items("a b\n\n  c d \n", separator: "\n") == ["a b", "c d"])
    }

    @Test
    func theTransformRunsAfterTrimmingAndEmptyResultsAreDropped() {
        #expect(ListText.items(" get , post,", separator: ",", transform: { $0.uppercased() }) == ["GET", "POST"])
        #expect(ListText.items("a, b", separator: ",", transform: { _ in "" }).isEmpty)
    }
}
