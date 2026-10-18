import WatcherCore

/// The traffic `start` prints: one line per flow once it has finished.
struct FinishedFlowLines {
    private var printed = Set<Flow.ID>()

    /// Flows update several times (streamed headers, WebSocket messages), so only the first finished update gets a line.
    mutating func line(for event: FlowEvent) -> String? {
        switch event {
        case let .updated(flow):
            guard flow.state != .pending, printed.insert(flow.id).inserted else { return nil }
            return line(for: flow)
        case let .removed(id):
            printed.remove(id)
        case .cleared:
            printed.removeAll()
        case .added:
            break
        }
        return nil
    }

    private func line(for flow: Flow) -> String {
        let milliseconds = Int((flow.duration ?? 0) * 1000)
        let tools = flow.appliedTools.isEmpty ? "" : "  [\(flow.appliedTools.joined(separator: ", "))]"
        let request = flow.request
        return "\(flow.sequence)  \(outcome(of: flow))  \(request.method)  \(request.url)  \(milliseconds)ms\(tools)"
    }

    /// The status, or why the flow ended when no response came.
    private func outcome(of flow: Flow) -> String {
        if let response = flow.response {
            return String(response.status)
        }
        return flow.state == .blocked ? "BLOCKED" : "ERR"
    }
}
