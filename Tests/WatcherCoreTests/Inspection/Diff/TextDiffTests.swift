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
}
