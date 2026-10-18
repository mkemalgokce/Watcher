import WatcherCore

extension BreakpointRule {
    /// What the rule stops: "request", "response" or "request + response".
    var phaseSummary: String {
        [onRequest ? "request" : nil, onResponse ? "response" : nil].compactMap(\.self).joined(separator: " + ")
    }
}
