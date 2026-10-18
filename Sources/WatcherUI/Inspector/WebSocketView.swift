import SwiftUI
import WatcherCore

struct WebSocketView: View {
    @Environment(WindowRouter.self) private var router
    let messages: [WebSocketMessage]

    var body: some View {
        let list = WebSocketMessageList(all: messages, hidesPingPong: router.hidePingPong)
        let shown = list.shown
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(list.countText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Hide ping/pong", isOn: Bindable(router).hidePingPong).toggleStyle(.switch).controlSize(.mini)
            }
            .padding(.horizontal, Metrics.gutter).padding(.vertical, 8)
            Divider()
            if shown.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(list.emptyText)
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
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
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
            Text(Timestamp(locale: locale, timeZone: timeZone).clock(message.date))
                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
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
