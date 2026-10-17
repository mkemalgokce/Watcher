import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct TextDiffTests {
    @Test
    func changedLineShowsAsRemovedThenAdded() {
        let lines = TextDiff.lines(from: "a\nb\nc", to: "a\nx\nc")
        #expect(lines.map(\.kind) == [.same, .removed, .added, .same])
        #expect(lines.filter { $0.kind == .added }.map(\.text) == ["x"])
    }

    @Test
    func sideBySidePairsRemovalsWithAdditions() {
        let rows = TextDiff.sideBySide(TextDiff.lines(from: "a\nb\nc", to: "a\nx\ny\nc"))
        #expect(rows.map { [$0.left?.text, $0.right?.text] } == [["a", "a"], ["b", "x"], [nil, "y"], ["c", "c"]])
        #expect(rows[1].left?.kind == .removed); #expect(rows[1].right?.kind == .added)
    }
}
