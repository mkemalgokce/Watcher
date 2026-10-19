import Foundation

public struct Header: Hashable, Codable, Sendable {
    public var name: String
    public var value: String
    public init(_ name: String, _ value: String) {
        self.name = name; self.value = value
    }

    /// A `Name: value` line, split at the first colon with the whitespace around both parts trimmed; nil without a colon.
    init?(line: String) {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        self.init(
            line[..<colon].trimmingCharacters(in: .whitespaces),
            line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        )
    }
}

public extension [Header] {
    func value(for name: String) -> String? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    mutating func set(_ name: String, _ value: String) {
        removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        append(Header(name, value))
    }
}
