import Foundation

public struct Header: Hashable, Codable, Sendable {
    public var name: String
    public var value: String
    public init(_ name: String, _ value: String) {
        self.name = name; self.value = value
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
