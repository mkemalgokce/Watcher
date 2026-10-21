import Foundation

/// A JSON document as a flat list of nodes, parents before their children, so a viewer can fold and unfold it.
/// Parsed by hand rather than with `JSONSerialization`, which loses key order and rewrites numbers.
/// Nodes keep byte ranges into the source instead of copies, so a large document stays cheap to hold.
public struct JSONTree: Sendable {
    public enum Kind: Sendable { case object, array, string, number, bool, null }

    public struct Node: Sendable {
        public let kind: Kind
        public let depth: Int
        /// Index of the parent node, -1 for the root.
        public let parent: Int
        /// Place among the parent's children.
        public let position: Int
        /// One past the last descendant: the next node that is not inside this one.
        public fileprivate(set) var end = 0
        public fileprivate(set) var childCount = 0
        fileprivate let key: Range<Int>?
        fileprivate(set) var value: Range<Int>

        public var isContainer: Bool {
            kind == .object || kind == .array
        }

        /// An empty `{}` or `[]` has nothing to open.
        public var isExpandable: Bool {
            isContainer && childCount > 0
        }
    }

    /// Deeper documents are refused: the parser recurses, and nothing readable nests this far.
    public static let maxDepth = 200
    /// Two levels open at first, or all of a document short enough to read at a glance.
    private static let openEverythingBelow = 300

    public private(set) var nodes: [Node]
    private let bytes: [UInt8]

    public static func parse(_ text: String) -> JSONTree? {
        var parser = Parser(bytes: Array(text.utf8))
        return parser.parse()
    }

    // MARK: Reading a node

    public func key(of index: Int) -> String? {
        nodes[index].key.map(unescaped)
    }

    /// What a node shows as its value: a string without its quotes and unescaped, anything else as written.
    public func text(of index: Int) -> String {
        let node = nodes[index]
        guard node.kind == .string else { return raw(node.value) }
        return unescaped(node.value.lowerBound + 1 ..< node.value.upperBound - 1)
    }

    /// The node's own JSON, exactly as it appeared in the source.
    public func json(of index: Int) -> String {
        raw(nodes[index].value)
    }

    /// Where the node sits, as a path the viewer's own filter understands: `$.users[0]["first name"]`.
    public func path(of index: Int) -> String {
        var steps: [String] = []
        var current = index
        while nodes[current].parent >= 0 {
            let node = nodes[current]
            steps.append(node.key == nil ? "[\(node.position)]" : Self.step(key(of: current) ?? ""))
            current = node.parent
        }
        return "$" + steps.reversed().joined()
    }

    /// The moment a number stands for when it reads as a Unix time in seconds or milliseconds between 2000 and 2100.
    public func timestamp(of index: Int) -> Date? {
        let node = nodes[index]
        guard node.kind == .number, let value = Int(raw(node.value)) else { return nil }
        let seconds = switch raw(node.value).count {
        case 10: Double(value)
        case 13: Double(value) / 1000
        default: nil as Double?
        }
        return seconds.flatMap { (946_684_800 ... 4_102_444_800).contains($0) ? Date(timeIntervalSince1970: $0) : nil }
    }

    // MARK: Folding

    /// The nodes to list while only `expanded` containers are open, in document order.
    public func visibleRows(expanded: Set<Int>) -> [Int] {
        var rows: [Int] = []
        var index = 0
        while index < nodes.count {
            rows.append(index)
            index = nodes[index].isExpandable && !expanded.contains(index) ? nodes[index].end : index + 1
        }
        return rows
    }

    public func defaultExpanded() -> Set<Int> {
        let limit = nodes.count <= Self.openEverythingBelow ? Int.max : 2
        return Set(nodes.indices.filter { nodes[$0].isExpandable && nodes[$0].depth < limit })
    }

    /// The node and everything inside it that can be opened.
    public func expandableNodes(in index: Int) -> [Int] {
        (index ..< nodes[index].end).filter { nodes[$0].isExpandable }
    }

    // MARK: Text

    // The viewer shows what it can; a stray invalid byte becomes a replacement character instead of hiding the value.
    // swiftlint:disable optional_data_string_conversion
    private func raw(_ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    private func unescaped(_ range: Range<Int>) -> String {
        let slice = bytes[range]
        guard slice.contains(0x5C) else { return String(decoding: slice, as: UTF8.self) }
        let quoted = Data([0x22] + slice + [0x22])
        let decoded = try? JSONSerialization.jsonObject(with: quoted, options: .fragmentsAllowed) as? String
        return decoded ?? String(decoding: slice, as: UTF8.self)
    }

    // swiftlint:enable optional_data_string_conversion

    private static func step(_ key: String) -> String {
        let plain = key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "$") }
        if plain, let first = key.first, !first.isNumber {
            return ".\(key)"
        }
        return "[\"\(key.replacingOccurrences(of: "\"", with: "\\\""))\"]"
    }
}

// MARK: Parser

private extension JSONTree {
    struct Invalid: Error {}

    struct Parser {
        let bytes: [UInt8]
        var position = 0
        var nodes: [Node] = []

        mutating func parse() -> JSONTree? {
            do {
                skipSpace()
                try value(depth: 0, parent: -1, position: 0, key: nil)
                skipSpace()
                return position == bytes.count ? JSONTree(nodes: nodes, bytes: bytes) : nil
            } catch {
                return nil
            }
        }

        private var next: UInt8? {
            position < bytes.count ? bytes[position] : nil
        }

        private mutating func skipSpace() {
            while let byte = next, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                position += 1
            }
        }

        private mutating func expect(_ byte: UInt8) throws {
            guard next == byte else { throw Invalid() }
            position += 1
        }

        private static func kind(startingWith byte: UInt8) -> Kind {
            switch byte {
            case UInt8(ascii: "{"): .object
            case UInt8(ascii: "["): .array
            case UInt8(ascii: "\""): .string
            case UInt8(ascii: "t"), UInt8(ascii: "f"): .bool
            case UInt8(ascii: "n"): .null
            default: .number
            }
        }

        private mutating func value(depth: Int, parent: Int, position place: Int, key: Range<Int>?) throws {
            guard depth <= JSONTree.maxDepth, let byte = next else { throw Invalid() }
            let start = position, index = nodes.count, kind = Self.kind(startingWith: byte)
            let node = Node(kind: kind, depth: depth, parent: parent, position: place, key: key, value: start ..< start)
            nodes.append(node)
            try read(kind, at: index, depth: depth, first: byte)
            nodes[index].value = start ..< position
            nodes[index].end = nodes.count
        }

        private mutating func read(_ kind: Kind, at index: Int, depth: Int, first: UInt8) throws {
            switch kind {
            case .object: try members(of: index, depth: depth, open: "{", close: "}", keyed: true)
            case .array: try members(of: index, depth: depth, open: "[", close: "]", keyed: false)
            case .string: _ = try string()
            case .bool: try literal(first == UInt8(ascii: "t") ? "true" : "false")
            case .null: try literal("null")
            case .number: try number()
            }
        }

        private mutating func members(
            of index: Int, depth: Int, open: Character, close: Character, keyed: Bool
        ) throws {
            try expect(open.asciiValue ?? 0)
            skipSpace()
            if next == close.asciiValue {
                position += 1
                return
            }
            var count = 0
            while true {
                skipSpace()
                var key: Range<Int>?
                if keyed {
                    key = try string()
                    skipSpace()
                    try expect(UInt8(ascii: ":"))
                    skipSpace()
                }
                try value(depth: depth + 1, parent: index, position: count, key: key)
                count += 1
                skipSpace()
                if next == UInt8(ascii: ",") {
                    position += 1
                    continue
                }
                try expect(close.asciiValue ?? 0)
                nodes[index].childCount = count
                return
            }
        }

        /// Moves past a string and returns its text between the quotes, still escaped.
        private mutating func string() throws -> Range<Int> {
            try expect(UInt8(ascii: "\""))
            let start = position
            while let byte = next {
                if byte == UInt8(ascii: "\"") {
                    defer { position += 1 }
                    return start ..< position
                }
                position += byte == UInt8(ascii: "\\") ? 2 : 1
            }
            throw Invalid()
        }

        private mutating func literal(_ word: String) throws {
            let letters = Array(word.utf8)
            let end = position + letters.count
            guard end <= bytes.count, Array(bytes[position ..< end]) == letters else { throw Invalid() }
            position += letters.count
        }

        private mutating func number() throws {
            let start = position
            while let byte = next, (0x30 ... 0x39).contains(byte) || "+-.eE".utf8.contains(byte) {
                position += 1
            }
            guard bytes[start ..< position].contains(where: { (0x30 ... 0x39).contains($0) }) else { throw Invalid() }
        }
    }
}

// MARK: Detecting documents

public extension JSONTree {
    /// A body above this stays as text: the tree keeps a node per value, and a viewer cannot make use of more.
    static let viewLimit = 8 * 1024 * 1024

    /// Longer values are not parsed just to decide whether to offer a JSON view.
    static let detectionLimit = 256 * 1024

    /// Whether `text` is a whole JSON object or array: a lone number, string or `[draft]` is not worth a viewer.
    static func isDocument(_ text: String) -> Bool {
        guard text.utf8.count <= detectionLimit,
              let first = text.utf8.first(where: { !$0.isASCIIWhitespace }),
              first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
        else { return false }
        return parse(text) != nil
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09
    }
}
