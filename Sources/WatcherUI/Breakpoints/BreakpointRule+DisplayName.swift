import WatcherCore

extension BreakpointRule {
    /// The rule's name, or its pattern when it has none.
    var displayName: String {
        name.isEmpty ? matching.pattern : name
    }
}
