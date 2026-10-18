import WatcherCore

/// A tool rule picked by URL, listed by its name.
protocol NamedMatchingRule: ToolRule {
    var name: String { get }
    var matching: MatchingRule { get }
}

extension NamedMatchingRule {
    /// The rule's name, or its pattern when it has none.
    var displayName: String {
        name.isEmpty ? matching.pattern : name
    }
}

extension BlockRule: NamedMatchingRule {}
extension AllowRule: NamedMatchingRule {}
extension MapLocalRule: NamedMatchingRule {}
extension MapRemoteRule: NamedMatchingRule {}
extension BreakpointRule: NamedMatchingRule {}
extension ScriptRule: NamedMatchingRule {}
extension PreviewerRule: NamedMatchingRule {}
extension ProtobufRule: NamedMatchingRule {}
