import Foundation
import Observation
import WatcherCore

/// One JSON value viewed on its own, such as a form field or a WebSocket message: filtered by a path or a jq program,
/// with keys sorted if asked, as a tree or as text. The filtering is the body viewer's, so both behave alike.
@MainActor @Observable
final class JSONDocumentModel {
    let source: String
    var showsTree = true
    var path = "" {
        didSet { refresh(ifChanged: oldValue, path) }
    }

    var sortsKeys = false {
        didSet { refresh(ifChanged: oldValue, sortsKeys) }
    }

    private(set) var prepared: BodyRendering.Prepared
    /// Nil when the shown text is not one JSON document (a filter that returned several values, or broken JSON).
    private(set) var tree: JSONTreeModel?

    init(source: String) {
        self.source = source
        prepared = Self.prepare(source, path: "", sortsKeys: false)
        tree = Self.tree(of: prepared)
    }

    /// The filter ran and found nothing, as opposed to text that was never JSON.
    var hasNoMatch: Bool {
        !path.isEmpty && !prepared.pathFailed && prepared.text.isEmpty
    }

    var minified: String {
        BodyFormatter.minified(prepared.text, language: .json)
    }

    private func refresh<Value: Equatable>(ifChanged old: Value, _ new: Value) {
        guard old != new else { return }
        prepared = Self.prepare(source, path: path, sortsKeys: sortsKeys)
        tree = Self.tree(of: prepared)
    }

    private static func prepare(_ source: String, path: String, sortsKeys: Bool) -> BodyRendering.Prepared {
        BodyRendering.prepare(
            Data(source.utf8), contentType: "application/json", mode: .pretty, sortKeys: sortsKeys, path: path,
            detectsGraphQL: false
        )
    }

    private static func tree(of prepared: BodyRendering.Prepared) -> JSONTreeModel? {
        JSONTree.parse(prepared.text).map(JSONTreeModel.init(tree:))
    }
}
