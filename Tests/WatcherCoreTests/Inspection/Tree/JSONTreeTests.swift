import Foundation
import Testing
@testable import WatcherCore

/// The JSON a body viewer folds and unfolds: key order and number spelling survive, bad JSON is refused, never half-read.
@Suite(.tags(.unit))
struct JSONTreeTests {
    private func tree(_ text: String) throws -> JSONTree {
        try #require(JSONTree.parse(text))
    }

    @Test
    func keepsKeyOrderAndKinds() throws {
        let tree = try tree(#"{"b":1,"a":[true,null,"x"]}"#)
        #expect(tree.nodes.map(\.kind) == [.object, .number, .array, .bool, .null, .string])
        #expect((0 ..< tree.nodes.count).map { tree.key(of: $0) } == [nil, "b", "a", nil, nil, nil])
    }

    @Test
    func countsChildrenAndMarksWhereASubtreeEnds() throws {
        let tree = try tree(#"{"a":{"x":1,"y":2},"b":3}"#)
        #expect(tree.nodes[0].childCount == 2 && tree.nodes[0].end == 5)
        #expect(tree.nodes[1].childCount == 2 && tree.nodes[1].end == 4)
        #expect(tree.nodes[4].end == 5)
        #expect(tree.nodes.map(\.depth) == [0, 1, 2, 2, 1])
    }

    @Test(arguments: [
        "", "{", #"{"a":}"#, "[1,]", #"{"a":1} x"#, #"{"a" 1}"#, "[1 2]", "tru", "-", #"{"a":"unterminated}"#, "{,}",
    ])
    func refusesWhatIsNotJSON(text: String) {
        #expect(JSONTree.parse(text) == nil)
    }

    @Test
    func refusesNestingDeepEnoughToOverflowTheStack() {
        let levels = JSONTree.maxDepth + 5
        let deep = String(repeating: "[", count: levels) + String(repeating: "]", count: levels)
        #expect(JSONTree.parse(deep) == nil)
        let fine = String(repeating: "[", count: 50) + String(repeating: "]", count: 50)
        #expect(JSONTree.parse(fine) != nil)
    }

    @Test(arguments: ["42", #""text""#, "null", "true", "[]", "{}", " \n{ } \n"])
    func acceptsAnyValueAtTheTop(text: String) {
        #expect(JSONTree.parse(text) != nil)
    }

    @Test
    func keepsNumbersAsWritten() throws {
        let tree = try tree("[1.0e5, -0.50, 12345678901234567890]")
        #expect([1, 2, 3].map { tree.text(of: $0) } == ["1.0e5", "-0.50", "12345678901234567890"])
    }

    @Test
    func stringsAreShownWithoutQuotesAndUnescaped() throws {
        let tree = try tree(#"{"k\"ey":"a\"bé\n"}"#)
        #expect(tree.key(of: 1) == #"k"ey"#)
        #expect(tree.text(of: 1) == "a\"bé\n")
    }

    @Test
    func rawJSONOfAContainerIsItsExactText() throws {
        let tree = try tree(#"{"a": {"x": [1, 2]}, "b": 3}"#)
        #expect(tree.json(of: 1) == #"{"x": [1, 2]}"#)
        #expect(tree.json(of: 0) == #"{"a": {"x": [1, 2]}, "b": 3}"#)
        #expect(tree.json(of: 4) == "2")
        #expect(tree.json(of: 5) == "3")
    }

    @Test
    func pathsUseDotsIndexesAndBracketsForOddKeys() throws {
        let tree = try tree(#"{"users":[{"na me":1,"id":2}],"a\"b":0}"#)
        #expect(tree.path(of: 0) == "$")
        #expect(tree.path(of: 1) == "$.users")
        #expect(tree.path(of: 2) == "$.users[0]")
        #expect(tree.path(of: 3) == #"$.users[0]["na me"]"#)
        #expect(tree.path(of: 4) == "$.users[0].id")
        #expect(tree.path(of: 5) == #"$["a\"b"]"#)
    }

    @Test
    func onlyANonEmptyContainerCanBeOpened() throws {
        let tree = try tree(#"{"a":{},"b":[],"c":[1],"d":1}"#)
        #expect(tree.nodes.map(\.isExpandable) == [true, false, false, true, false, false])
    }

    @Test
    func collapsedSubtreesAreSkippedWhenListingRows() throws {
        let tree = try tree(#"{"a":{"x":1,"y":2},"b":[3]}"#)
        #expect(tree.visibleRows(expanded: [0, 1, 4]) == [0, 1, 2, 3, 4, 5])
        #expect(tree.visibleRows(expanded: [0]) == [0, 1, 4])
        #expect(tree.visibleRows(expanded: []) == [0])
    }

    @Test
    func aBigDocumentOpensTwoLevelsAndASmallOneOpensFully() throws {
        let small = try tree(#"{"a":{"b":{"c":{"d":1}}}}"#)
        #expect(small.defaultExpanded() == [0, 1, 2, 3])
        let items = (0 ..< 400).map { #"{"k":{"deep":[1]}}"# + ($0 == 399 ? "" : ",") }.joined()
        let big = try tree("[" + items + "]")
        let opened = big.defaultExpanded()
        #expect(opened.contains(0) && opened.contains(1))
        #expect(!opened.contains(2), "the third level stays folded in a long document")
    }

    @Test(arguments: [
        ("1700000000", true), ("1700000000000", true), ("123", false), ("17000000000", false),
        ("1700000000.5", false), ("-1700000000", false), ("99999999999999", false),
    ])
    func recognisesUnixTimestamps(text: String, isDate: Bool) throws {
        let tree = try tree("[\(text)]")
        #expect((tree.timestamp(of: 1) != nil) == isDate)
    }

    @Test
    func secondsAndMillisecondsGiveTheSameMoment() throws {
        let tree = try tree("[1700000000, 1700000000000]")
        #expect(tree.timestamp(of: 1) == tree.timestamp(of: 2))
        #expect(tree.timestamp(of: 1)?.timeIntervalSince1970 == 1_700_000_000)
    }

    @Test
    func handlesNonASCIIKeysAndValues() throws {
        let tree = try tree(#"{"şehir":"İstanbul 🌍"}"#)
        #expect(tree.key(of: 1) == "şehir")
        #expect(tree.text(of: 1) == "İstanbul 🌍")
    }
}
