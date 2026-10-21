import SwiftUI
import WatcherCore

/// The tree for a JSON or YAML body. Short text is parsed at once so the first frame already shows it; long text is parsed off
/// the main thread. Text that does not parse, or is too long, is shown as text instead of an empty tree.
struct JSONBodyTree: View {
    private enum Phase {
        case loading, ready(JSONTreeModel), text
    }

    /// What the text is written in; YAML is turned into JSON on the way to the tree.
    enum Notation { case json, yaml }

    let text: String
    var notation = Notation.json
    var fontSize = 12.0
    @State private var phase: Phase
    @State private var builtFrom: String

    private static let immediateLimit = 256 * 1024

    init(text: String, notation: Notation = .json, fontSize: Double = 12) {
        self.text = text
        self.notation = notation
        self.fontSize = fontSize
        _builtFrom = State(initialValue: text)
        let small = text.utf8.count <= Self.immediateLimit
        _phase = State(initialValue: small ? Self.phase(for: text, notation) : .loading)
    }

    var body: some View {
        Group {
            switch phase {
            case let .ready(model):
                JSONTreeView(model: model, fontSize: fontSize)
                    .overlay(alignment: .topTrailing) {
                        JSONFoldButtons(model: model).background(.regularMaterial, in: Capsule()).padding(6)
                    }
            case .text:
                SyntaxTextView(text, language: notation == .json ? .json : .plain, wraps: true, fontSize: fontSize)
            case .loading:
                ProgressView("Reading \(Format.bytes(text.utf8.count))…").controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: text) {
            guard isLoading || text != builtFrom else { return }
            builtFrom = text
            let (source, notation) = (text, notation)
            let tree = text.utf8.count > JSONTree.viewLimit ? nil
                : await Task.detached(priority: .userInitiated) { Self.tree(of: source, notation) }.value
            guard !Task.isCancelled else { return }
            phase = tree.map { .ready(JSONTreeModel(tree: $0)) } ?? .text
        }
    }

    private var isLoading: Bool {
        if case .loading = phase {
            true
        } else {
            false
        }
    }

    private static func phase(for text: String, _ notation: Notation) -> Phase {
        tree(of: text, notation).map { .ready(JSONTreeModel(tree: $0)) } ?? .text
    }

    private nonisolated static func tree(of text: String, _ notation: Notation) -> JSONTree? {
        switch notation {
        case .json: JSONTree.parse(text)
        case .yaml: YAMLDocument.json(from: text).flatMap(JSONTree.parse)
        }
    }
}

/// Open or close every container at once.
struct JSONFoldButtons: View {
    let model: JSONTreeModel

    var body: some View {
        HStack(spacing: 2) {
            IconButton("Expand All", symbol: "chevron.down.2") { model.expandAll() }
            IconButton("Collapse All", symbol: "chevron.up.2") { model.collapseAll() }
        }
    }
}
