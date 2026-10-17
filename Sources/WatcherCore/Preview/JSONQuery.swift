import Foundation

/// Small JSON path language for filtering a response in the viewer:
/// `users[0].name`, `$.items[*].id`, `..email` (any depth) or just `email` (same as `..email`).
public enum JSONQuery {
    private enum Step { case key(String), index(Int), wildcard, descend(String) }

    /// Matching values as pretty JSON; empty string when nothing matches; nil when `data` is not JSON.
    public static func run(_ query: String, on data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        var nodes: [Any] = [root]
        for step in steps(query) {
            nodes = nodes.flatMap { apply(step, to: $0) }
        }
        guard !nodes.isEmpty else { return "" }
        let result: Any = nodes.count == 1 ? nodes[0] : nodes
        guard let output = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return "" }
        return String(decoding: output, as: UTF8.self)
    }

    private static func steps(_ query: String) -> [Step] {
        var text = query.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("$") {
            text.removeFirst()
        }
        if !text.contains(where: { ".[".contains($0) }), !text.isEmpty {
            return [.descend(text)]
        }
        var steps: [Step] = [], index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("..") {
                index = text.index(index, offsetBy: 2)
                let name = text[index...].prefix { $0 != "." && $0 != "[" }
                steps.append(.descend(String(name))); index = text.index(index, offsetBy: name.count)
            } else if text[index] == "." {
                index = text.index(after: index)
                let name = text[index...].prefix { $0 != "." && $0 != "[" }
                if !name.isEmpty {
                    steps.append(name == "*" ? .wildcard : .key(String(name)))
                }
                index = text.index(index, offsetBy: name.count)
            } else if text[index] == "[", let close = text[index...].firstIndex(of: "]") {
                let inner = text[text.index(after: index) ..< close].trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
                steps.append(inner == "*" ? .wildcard : Int(inner).map(Step.index) ?? .key(inner))
                index = text.index(after: close)
            } else {
                let name = text[index...].prefix { $0 != "." && $0 != "[" }
                steps.append(.key(String(name))); index = text.index(index, offsetBy: name.count)
            }
        }
        return steps
    }

    private static func apply(_ step: Step, to node: Any) -> [Any] {
        switch (step, node) {
        case let (.key(key), object as [String: Any]): object[key].map { [$0] } ?? []
        case let (.index(position), array as [Any]): array.indices.contains(position) ? [array[position]] : []
        case let (.wildcard, array as [Any]): array
        case let (.wildcard, object as [String: Any]): object.keys.sorted().compactMap { object[$0] }
        case let (.descend(key), _): descend(key, in: node)
        default: []
        }
    }

    private static func descend(_ key: String, in node: Any) -> [Any] {
        switch node {
        case let object as [String: Any]:
            object.keys.sorted().flatMap { name in (name == key ? [object[name]!] : []) + descend(key, in: object[name]!) }
        case let array as [Any]: array.flatMap { descend(key, in: $0) }
        default: []
        }
    }
}
