import SwiftUI
import WatcherCore

/// A JSON document as rows that fold: a chevron on every container, guide lines for the nesting, values coloured by
/// type. A `List`, so only the rows on screen exist however long the document is.
struct JSONTreeView: View {
    let model: JSONTreeModel
    var fontSize = 12.0
    @State private var selection: Int?

    var body: some View {
        List(model.rows, id: \.self, selection: $selection) { index in
            JSONRow(model: model, index: index, fontSize: fontSize)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, fontSize + 7)
        .onKeyPress(.rightArrow) { fold(open: true) }
        .onKeyPress(.leftArrow) { fold(open: false) }
        .accessibilityLabel("JSON tree")
    }

    /// Right opens the selected container; left closes it, or moves to its parent when it is already closed.
    private func fold(open: Bool) -> KeyPress.Result {
        guard let selection else { return .ignored }
        let node = model.tree.nodes[selection]
        if node.isExpandable, model.isExpanded(selection) != open {
            model.toggle(selection)
        } else if !open, node.parent >= 0 {
            self.selection = node.parent
        } else {
            return .ignored
        }
        return .handled
    }
}

private struct JSONRow: View {
    @Environment(RequestActions.self) private var actions
    @Environment(\.timestamp) private var timestamp
    let model: JSONTreeModel
    let index: Int
    let fontSize: Double

    private static let indent = 14.0
    /// A single row never draws more than this much of a value; the tooltip and Copy have all of it.
    private static let shownLimit = 400

    var body: some View {
        let tree = model.tree
        let node = tree.nodes[index]
        HStack(spacing: 0) {
            ForEach(0 ..< node.depth, id: \.self) { _ in
                Rectangle().fill(Color.secondary.opacity(0.22)).frame(width: 1)
                    .frame(width: Self.indent, alignment: .leading)
            }
            disclosure(node)
            line(node, in: tree)
            Spacer(minLength: 0)
        }
        .font(.code(size: fontSize))
        .lineLimit(1)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.toggle(index) })
        .contextMenu { menu(node, in: tree) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(node, in: tree))
    }

    @ViewBuilder private func disclosure(_ node: JSONTree.Node) -> some View {
        if node.isExpandable {
            let open = model.isExpanded(index)
            Button {
                // Option-click folds or unfolds everything inside, as in Xcode and Finder.
                if NSEvent.modifierFlags.contains(.option) {
                    if open {
                        model.collapseSubtree(index)
                    } else {
                        model.expandSubtree(index)
                    }
                } else {
                    model.toggle(index)
                }
            } label: {
                Image(systemName: "chevron.right").font(.code(size: fontSize - 3, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary)
                    .frame(width: Self.indent, height: fontSize + 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Collapse" : "Expand")
        } else {
            Color.clear.frame(width: Self.indent)
        }
    }

    private func line(_ node: JSONTree.Node, in tree: JSONTree) -> some View {
        HStack(spacing: 0) {
            if let key = tree.key(of: index) {
                Text(verbatim: key).foregroundStyle(Color(nsColor: SyntaxTextView.Theme.color(.key)))
                Text(verbatim: ": ").foregroundStyle(.secondary)
            }
            value(node, in: tree)
        }
    }

    @ViewBuilder private func value(_ node: JSONTree.Node, in tree: JSONTree) -> some View {
        switch node.kind {
        case .object, .array:
            let open = model.isExpanded(index)
            let (opening, closing) = node.kind == .object ? ("{", "}") : ("[", "]")
            if node.childCount == 0 {
                Text(verbatim: opening + closing).foregroundStyle(.secondary)
            } else {
                Text(verbatim: open ? opening : "\(opening) … \(closing)").foregroundStyle(.secondary)
                Text(verbatim: "  \(Self.count(node))").font(.code(size: fontSize - 1)).foregroundStyle(.tertiary)
            }
        case .string:
            let text = tree.text(of: index)
            Text(verbatim: "\"\(Self.oneLine(text))\"")
                .foregroundStyle(Color(nsColor: SyntaxTextView.Theme.color(.string)))
                .help(String(text.prefix(2000)))
        case .number:
            Text(verbatim: tree.text(of: index)).foregroundStyle(Color(nsColor: SyntaxTextView.Theme.color(.number)))
            if let date = tree.timestamp(of: index) {
                Image(systemName: "clock").font(.code(size: fontSize - 2)).foregroundStyle(.tertiary)
                    .padding(.leading, 6).help(timestamp.complete(date)).accessibilityLabel(timestamp.complete(date))
            }
        case .bool, .null:
            Text(verbatim: tree.text(of: index)).foregroundStyle(Color(nsColor: SyntaxTextView.Theme.color(.keyword)))
        }
    }

    @ViewBuilder private func menu(_ node: JSONTree.Node, in tree: JSONTree) -> some View {
        Button("Copy Value") { actions.copy(tree.text(of: index), "Value copied") }
        Button("Copy as JSON") { actions.copy(tree.json(of: index), "JSON copied") }
        if let key = tree.key(of: index) {
            Button("Copy Key") { actions.copy(key, "Key copied") }
        }
        Button("Copy Path") { actions.copy(tree.path(of: index), "Path copied") }
        if node.isExpandable {
            Divider()
            if model.isExpanded(index) {
                Button("Collapse Everything Inside") { model.collapseSubtree(index) }
            }
            Button("Expand Everything Inside") { model.expandSubtree(index) }
        }
    }

    private func accessibilityText(_ node: JSONTree.Node, in tree: JSONTree) -> String {
        let name = tree.key(of: index).map { "\($0): " } ?? ""
        return node.isContainer ? name + Self.count(node) : name + tree.text(of: index)
    }

    private static func count(_ node: JSONTree.Node) -> String {
        let (one, many) = node.kind == .object ? ("key", "keys") : ("item", "items")
        return "\(node.childCount) \(node.childCount == 1 ? one : many)"
    }

    /// A string with line breaks would push the next row's text around; show them as symbols.
    private static func oneLine(_ text: String) -> String {
        let cut = text.count > shownLimit ? String(text.prefix(shownLimit)) + "…" : text
        return cut.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\t", with: "⇥")
    }
}
