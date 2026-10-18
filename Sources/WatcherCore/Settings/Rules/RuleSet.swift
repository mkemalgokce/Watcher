/// A tool's master switch plus its rules.
public struct RuleSet<Rule: ToolRule>: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var rules: [Rule]

    public init(isEnabled: Bool = false, rules: [Rule] = []) {
        self.isEnabled = isEnabled; self.rules = rules
    }

    /// Rules that should currently take effect.
    public var active: [Rule] {
        isEnabled ? rules.filter(\.isEnabled) : []
    }

    /// Folder names in the order they first appear.
    public var folders: [String] {
        var seen: [String] = []
        for case let name? in rules.map(\.folder) where !seen.contains(name) {
            seen.append(name)
        }
        return seen
    }

    /// Switches every rule filed under `name` on or off.
    public mutating func setFolder(_ name: String, enabled: Bool) {
        for index in rules.indices where rules[index].folder == name {
            rules[index].isEnabled = enabled
        }
    }
}
