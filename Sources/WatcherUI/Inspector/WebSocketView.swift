import SwiftUI
import WatcherCore

struct WebSocketView: View {
    @Environment(AppModel.self) private var model
    let messages: [WebSocketMessage]

    var body: some View {
        @Bindable var model = model
        let shown = messages.filter { !model.hidePingPong || ($0.kind != .ping && $0.kind != .pong) }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(shown.count) of \(messages.count) messages").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Hide ping/pong", isOn: $model.hidePingPong).toggleStyle(.switch).controlSize(.mini)
            }
            .padding(.horizontal, Metrics.gutter).padding(.vertical, 8)
            Divider()
            if shown.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(messages.isEmpty ? "The socket has not sent anything yet." : "Only ping/pong frames so far.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, message in
                            MessageRow(message: message)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct MessageRow: View {
    let message: WebSocketMessage

    var body: some View {
        let outgoing = message.direction == .clientToServer
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: outgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(outgoing ? Palette.request : Palette.response)
                .accessibilityLabel(outgoing ? "Sent" : "Received")
            Pill(text: message.kind.rawValue, monospaced: true).frame(width: 64, alignment: .leading)
            Text(preview).font(.system(.callout, design: .monospaced)).lineLimit(4).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(message.date.formatted(date: .omitted, time: .standard)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Metrics.gutter).padding(.vertical, 6)
    }

    private var preview: String {
        if message.isCompressed {
            return "<compressed, \(message.payload.count) bytes>"
        }
        return BodyPreview.text(message.payload, contentType: message.kind == .text ? "text/plain" : nil)
    }
}
