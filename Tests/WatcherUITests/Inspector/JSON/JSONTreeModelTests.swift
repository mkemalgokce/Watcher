import Testing
import WatcherCore
@testable import WatcherUI

/// Which containers of a JSON document are open, and the rows that leaves on screen.
@MainActor
@Suite(.tags(.unit))
struct JSONTreeModelTests {
    private func model(_ text: String) throws -> JSONTreeModel {
        try JSONTreeModel(tree: #require(JSONTree.parse(text)))
    }

    private let nested = #"{"a":{"x":1,"y":{"z":2}},"b":[3]}"#

    @Test
    func startsWithTheDefaultContainersOpen() throws {
        let model = try model(nested)
        #expect(model.rows == [0, 1, 2, 3, 4, 5, 6], "a small document opens fully")
    }

    @Test
    func togglingFoldsAndUnfoldsAContainer() throws {
        let model = try model(nested)
        model.toggle(1)
        #expect(model.isExpanded(1) == false)
        #expect(model.rows == [0, 1, 5, 6])
        model.toggle(1)
        #expect(model.rows == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test
    func aValueWithNothingInsideCannotBeToggled() throws {
        let model = try model(#"{"a":1,"b":{}}"#)
        let before = model.rows
        model.toggle(1)
        model.toggle(2)
        #expect(model.rows == before)
    }

    @Test
    func collapseAllLeavesTheTopLevelVisible() throws {
        let model = try model(nested)
        model.collapseAll()
        #expect(model.rows == [0])
        #expect(model.isExpanded(0) == false)
    }

    @Test
    func expandAllOpensEveryContainer() throws {
        let model = try model(nested)
        model.collapseAll()
        model.expandAll()
        #expect(model.rows == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test
    func aSubtreeCanBeOpenedAndClosedOnItsOwn() throws {
        let model = try model(nested)
        model.collapseAll()
        model.toggle(0)
        model.expandSubtree(1)
        #expect(model.rows == [0, 1, 2, 3, 4, 5], "b was not part of the subtree, so it stays folded")
        model.collapseSubtree(1)
        #expect(model.rows == [0, 1, 5])
        #expect(model.isExpanded(0), "the parent stays open")
    }

    @Test
    func aLongDocumentOpensOnlyTwoLevels() throws {
        let items = (0 ..< 400).map { _ in #"{"k":{"d":[1]}}"# }.joined(separator: ",")
        let model = try model("[\(items)]")
        #expect(model.isExpanded(1))
        #expect(model.isExpanded(2) == false)
    }
}
