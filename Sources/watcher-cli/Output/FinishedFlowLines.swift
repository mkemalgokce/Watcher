import WatcherCore

/// The traffic `start` prints: one line per flow once it has finished.
struct FinishedFlowLines {
    private var printed = Set<Flow.ID>()

    /// Flows update several times (streamed headers, WebSocket messages), so only the first finished update gets a line.
    mutating func line(for event: FlowEvent) -> String? {
        guard case let .updated(flow) = event, flow.state != .pending, let response = flow.response,
              printed.insert(flow.id).inserted else { return nil }
        let milliseconds = Int((flow.duration ?? 0) * 1000)
        let tools = flow.appliedTools.isEmpty ? "" : "  [\(flow.appliedTools.joined(separator: ", "))]"
        let request = flow.request
        return "\(flow.sequence)  \(response.status)  \(request.method)  \(request.url)  \(milliseconds)ms\(tools)"
    }
}
