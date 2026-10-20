import Foundation
import Testing
@testable import WatcherUI

/// A JSON value on its own: filtered by a path or jq, optionally with sorted keys, shown as a tree or as text.
@MainActor
@Suite(.tags(.unit))
struct JSONDocumentModelTests {
    private let source = #"{"b":1,"a":{"name":"Ada","tags":["x","y"]}}"#

    @Test
    func showsTheWholeDocumentAsATreeFirst() {
        let model = JSONDocumentModel(source: source)
        #expect(model.showsTree)
        #expect(model.tree != nil)
        #expect(model.prepared.text.contains("\"name\": \"Ada\""), "pretty-printed")
    }

    @Test
    func theFilterNarrowsTheTreeToWhatMatches() {
        let model = JSONDocumentModel(source: source)
        model.path = "a.tags"
        #expect(model.prepared.pathFailed == false)
        #expect(model.tree?.tree.nodes.count == 3, "the array and its two items")
    }

    @Test
    func aFilterThatMatchesNothingLeavesNothingToShow() {
        let model = JSONDocumentModel(source: source)
        model.path = "nothing.here"
        #expect(model.prepared.text.isEmpty)
        #expect(model.tree == nil)
        #expect(model.hasNoMatch)
    }

    @Test
    func clearingTheFilterBringsTheDocumentBack() {
        let model = JSONDocumentModel(source: source)
        model.path = "b"
        model.path = ""
        #expect(model.tree?.tree.nodes.count == 7)
    }

    @Test
    func sortingKeysReordersThem() throws {
        let model = JSONDocumentModel(source: source)
        model.sortsKeys = true
        let text = model.prepared.text
        #expect(try #require(text.range(of: "\"a\"")).lowerBound < #require(text.range(of: "\"b\"")).lowerBound)
    }

    @Test
    func textThatIsNotJSONHasNoTree() {
        let model = JSONDocumentModel(source: "{broken")
        #expect(model.tree == nil)
        #expect(!model.hasNoMatch, "nothing was filtered out; there was never anything to show as a tree")
        #expect(model.prepared.text.contains("broken"))
    }

    @Test
    func theMinifiedCopyDropsTheWhitespace() {
        let model = JSONDocumentModel(source: "{\n  \"a\": 1,\n  \"b\": [ 1, 2 ]\n}")
        #expect(model.minified == #"{"a":1,"b":[1,2]}"#)
    }

    @Test
    func aFilterKeepsTheTreeOpenedByTheUserOnlyUntilTheRowsChange() {
        let model = JSONDocumentModel(source: source)
        model.tree?.collapseAll()
        model.path = "a"
        #expect(model.tree?.rows.count ?? 0 > 1, "a new result starts from its default folding")
    }

    @Test
    func aGraphQLShapedEnvelopeIsStillJSON() {
        let model = JSONDocumentModel(source: #"{"query":"{ viewer { id } }","variables":{"a":1}}"#)
        #expect(model.prepared.language == .json)
        #expect(model.tree?.tree.nodes.count == 4)
    }
}
