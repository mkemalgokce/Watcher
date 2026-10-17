import Foundation

public protocol ToolRule: Codable, Equatable, Sendable {
    var isEnabled: Bool { get set }
    /// Optional folder the rule is filed under; rules of one folder can be switched on or off together.
    var folder: String? { get set }
}
