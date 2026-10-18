import WatcherCore

/// How a request's state reads in the list (short) and in the inspector (with the reason phrase).
extension Flow {
    var listStatusText: String {
        switch state {
        case .pending: "…"
        case .failed: "Failed"
        case .blocked, .completed: response.map { "\($0.status)" } ?? "—"
        }
    }

    var inspectorStatusText: String {
        switch state {
        case .pending: "Pending"
        case .failed: "Failed"
        case .blocked, .completed: response.map { "\($0.status) \(HTTPStatus.reason($0.status))" } ?? "—"
        }
    }

    /// For VoiceOver: the status with its reason, or what the pill otherwise says.
    var statusAccessibilityLabel: String {
        response.map { "Status \($0.status) \(HTTPStatus.reason($0.status))" } ?? listStatusText
    }
}
