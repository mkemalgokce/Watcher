import SwiftUI
import WatcherCore

struct StatusPill: View {
    let flow: Flow

    private var text: String {
        switch flow.state {
        case .pending: "…"
        case .failed: "Failed"
        case .blocked, .completed: flow.response.map { "\($0.status)" } ?? "—"
        }
    }

    var body: some View {
        let tint = Palette.status(flow.response?.status, failed: flow.state == .failed)
        HStack(spacing: 4) {
            Text(text).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(tint)
                .padding(.horizontal, 6).padding(.vertical, 1).background(tint.opacity(0.14), in: Capsule())
            if !flow.appliedTools.isEmpty {
                Image(systemName: "wrench.adjustable").font(.caption2).foregroundStyle(Palette.modified)
                    .help("Changed by \(flow.appliedTools.joined(separator: ", "))").accessibilityLabel("changed by a tool")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(flow.response.map { "Status \($0.status) \(HTTPStatus.reason($0.status))" } ?? text)
    }
}
