import Foundation
import Yams

/// YAML written out as JSON text, so the one tree viewer shows both. Yams reads the YAML; its `load` returns dictionaries,
/// which lose key order, so the document is walked as a `Node` tree and written in order here.
public enum YAMLDocument {
    private struct Refused: Error {}

    /// The YAML as JSON, or nil when it is not a map or list (a lone word is valid YAML, but not worth a tree), does not
    /// parse, or aliases expand past what the viewer can show. Several documents become one array.
    public static func json(from yaml: String) -> String? {
        guard var documents = try? Yams.compose_all(yaml: yaml) else { return nil }
        var writer = Writer()
        var written: [String] = []
        while let root = documents.next() {
            guard let text = try? writer.document(root) else { return nil }
            written.append(text)
        }
        guard documents.error == nil, !written.isEmpty else { return nil }
        return written.count == 1 ? written[0] : "[" + written.joined(separator: ",") + "]"
    }

    private struct Writer {
        private var anchors: [String: Node] = [:]
        private var out = ""

        mutating func document(_ root: Node) throws -> String {
            anchors = [:]
            out = ""
            guard root.mapping != nil || root.sequence != nil || root.isAlias else { throw Refused() }
            try write(root)
            return out
        }

        private mutating func write(_ node: Node) throws {
            // Aliases can nest into an output that grows exponentially; stop when it is more than a viewer can use.
            guard out.utf8.count <= JSONTree.viewLimit else { throw Refused() }
            if let anchor = node.anchor {
                anchors[anchor.rawValue] = node
            }
            switch node {
            case let .alias(alias):
                guard let target = anchors[alias.anchor.rawValue] else { throw Refused() }
                try write(target)
            case let .mapping(mapping):
                out += "{"
                for (index, pair) in mapping.enumerated() {
                    out += index == 0 ? "" : ","
                    out += Self.quoted(pair.key.string ?? "") + ":"
                    try write(pair.value)
                }
                out += "}"
            case let .sequence(sequence):
                out += "["
                for (index, element) in sequence.enumerated() {
                    out += index == 0 ? "" : ","
                    try write(element)
                }
                out += "]"
            case .scalar:
                out += Self.scalar(node)
            }
        }

        /// Yams gives each scalar the Swift type its YAML tag names, so a quoted "123" stays a string. JSON has no
        /// infinity or NaN and no hex spelling, so what it cannot say as a number is kept as text.
        private static func scalar(_ node: Node) -> String {
            switch node.any {
            case is NSNull: "null"
            case let value as Bool: value ? "true" : "false"
            case let value as Int: String(value)
            case let value as Double where value.isFinite: String(value)
            default: quoted(node.string ?? "")
            }
        }

        private static func quoted(_ text: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed)
            return data?.lossyUTF8 ?? "\"\""
        }
    }
}

private extension Node {
    var isAlias: Bool {
        if case .alias = self {
            true
        } else {
            false
        }
    }
}
