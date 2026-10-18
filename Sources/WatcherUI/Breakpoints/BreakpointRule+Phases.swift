import WatcherCore

extension BreakpointRule {
    /// What the rule stops: "request", "response" or "request + response".
    var phaseSummary: String {
        [onRequest ? "request" : nil, onResponse ? "response" : nil].compactMap(\.self).joined(separator: " + ")
    }

    /// One line for the rule list in text form: on or off, its title and what it stops.
    var summaryLine: String {
        "\(isEnabled ? "on " : "off") \(displayName) · \(phaseSummary)"
    }
}
