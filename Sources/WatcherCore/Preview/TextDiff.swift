import Foundation

/// Line-based diff (longest common subsequence) for comparing two bodies.
public enum TextDiff {
    public struct Line: Equatable, Sendable {
        public enum Kind: Sendable { case same, added, removed }
        public let kind: Kind
        public let text: String
    }

    // shortcut: O(n*m) table, so very long inputs fall back to a whole-body replace; switch to Myers if that matters.
    static let maxLines = 3000

    public static func lines(from old: String, to new: String) -> [Line] {
        let a = old.components(separatedBy: "\n"), b = new.components(separatedBy: "\n")
        guard a.count <= maxLines, b.count <= maxLines else {
            return a.map { Line(kind: .removed, text: $0) } + b.map { Line(kind: .added, text: $0) }
        }
        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [Line] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                result.append(Line(kind: .same, text: a[i])); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                result.append(Line(kind: .removed, text: a[i])); i += 1
            } else {
                result.append(Line(kind: .added, text: b[j])); j += 1
            }
        }
        result += a[i...].map { Line(kind: .removed, text: $0) }
        result += b[j...].map { Line(kind: .added, text: $0) }
        return result
    }

    public struct Row: Equatable, Sendable {
        public let left: Line?
        public let right: Line?
    }

    /// Two-column view of an inline diff: unchanged lines on both sides, and each run of removals paired with the run of additions that follows.
    public static func sideBySide(_ lines: [Line]) -> [Row] {
        var rows: [Row] = [], removed: [Line] = [], added: [Line] = []
        func flush() {
            for index in 0 ..< max(removed.count, added.count) {
                rows.append(Row(left: removed.indices.contains(index) ? removed[index] : nil, right: added.indices.contains(index) ? added[index] : nil))
            }
            removed = []; added = []
        }
        for line in lines {
            switch line.kind {
            case .same: flush(); rows.append(Row(left: line, right: line))
            case .removed: if !added.isEmpty {
                    flush()
                }; removed.append(line)
            case .added: added.append(line)
            }
        }
        flush()
        return rows
    }
}
