import SwiftUI
import WatcherCore

/// One side of an exchange (the request or the response) with its own sections:
/// Headers, Params (request only), Body, Cookies and the Raw message.
struct MessagePanel: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    let flow: Flow
    let side: MessageSide
    /// In a narrow inspector the title becomes the Request / Response switch, so switching costs no extra row.
    var switchesSide = false

    enum Section: String, CaseIterable {
        case headers = "Headers", params = "Params", body = "Body", cookies = "Cookies", raw = "Raw"
        /// Response side only: WebSocket frames, and the output of Tools ▸ Previewers.
        case messages = "Messages", previewers = "Previewers"
        /// Base64 payloads found inside the body (images, PDFs, JSON, files).
        case decoded = "Decoded"
        var symbol: String {
            switch self {
            case .decoded: "wand.and.stars"
            case .messages: "bubble.left.and.bubble.right"
            case .previewers: "eye"
            case .headers: "list.bullet.rectangle"
            case .params: "slider.horizontal.3"
            case .body: "doc.plaintext"
            case .cookies: "tag"
            case .raw: "text.alignleft"
            }
        }
    }

    private var content: MessagePanelViewModel {
        MessagePanelViewModel(
            flow: flow,
            side: side,
            previewersActive: !model.settings.previewers.active.isEmpty,
            embedded: EmbeddedDataIndex.shared.segments(in: flow, side: side)
        )
    }

    private var section: Section {
        content.section(chosen: model.viewer.section(for: side).rawValue)
    }

    private var headers: [Header] {
        content.headers
    }

    private var fields: [FormField] {
        content.fields
    }

    private var cookies: [CookieEntry] {
        content.cookies
    }

    private var embedded: [Base64Segment] {
        content.embedded
    }

    private var available: [Section] {
        content.available
    }

    private func count(_ section: Section) -> Int? {
        content.count(section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if side == .response, flow.response == nil {
                PendingResponse(flow: flow)
            } else {
                switch section {
                case .headers: KeyValueTable(rows: KeyValueRow.headers(headers), emptyText: "No headers.")
                case .params: KeyValueTable(rows: KeyValueRow.fields(fields), emptyText: "No query parameters or form fields.")
                case .body: BodyViewer(flow: flow, side: side, options: model.viewer)
                case .cookies: KeyValueTable(
                        rows: KeyValueRow.cookies(cookies, secureConnection: flow.request.scheme == "https"),
                        emptyText: side == .request ? "No cookies were sent." : "The server set no cookies."
                    )
                case .raw: RawMessage(flow: flow, side: side)
                case .messages: WebSocketView(messages: flow.webSocketMessages)
                case .previewers: PreviewsView(flow: flow)
                case .decoded: EmbeddedDataView(segments: embedded)
                }
            }
        }
        .padding(Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if switchesSide {
                    @Bindable var model = model
                    TabStrip(items: [
                        TabItem(id: MessageSide.request, title: "Request", symbol: "arrow.up.circle", shortcut: "⌥⌘["),
                        TabItem(id: MessageSide.response, title: "Response", symbol: "arrow.down.circle", shortcut: "⌥⌘]"),
                    ], selection: Bindable(router).exchangeSide)
                } else {
                    Label(side == .request ? "Request" : "Response", systemImage: side == .request ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.headline).foregroundStyle(side == .request ? Palette.request : Palette.response)
                        .labelStyle(TintedIconLabelStyle())
                }
                // The summary above already shows the status; repeating it here only matters when both panels sit side by side.
                if !switchesSide, side == .response, flow.response != nil {
                    StatusPill(flow: flow)
                }
                Spacer(minLength: 4)
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            TabStrip(items: available.map { item in
                TabItem(id: item, title: item.rawValue, symbol: item.symbol, badge: count(item).flatMap { $0 > 0 ? "\($0)" : nil })
            }, selection: Binding(get: { section }, set: { model.viewer.choose($0, for: side) }))
                .accessibilityLabel("\(side == .request ? "Request" : "Response") section")
        }
    }

    private var detail: String {
        content.detail
    }
}

/// What to show while there is no response: waiting, failed with the reason and what to try, or blocked by a tool.
private struct PendingResponse: View {
    let flow: Flow

    var body: some View {
        switch flow.state {
        case .failed:
            ContentUnavailableView {
                Label("No response", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.error)
            } description: {
                Text(flow.error ?? "The connection failed before a response arrived.")
                Text("Check the host name and that the server is reachable. For HTTPS, the app may reject Watcher's certificate (SSL pinning).")
            }
        case .blocked:
            ContentUnavailableView("Blocked", systemImage: "nosign", description: Text("A Block List rule stopped this request; it never reached the server."))
        default:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for the response…").foregroundStyle(.secondary)
                if !flow.appliedTools.isEmpty {
                    Text("Touched by \(flow.appliedTools.joined(separator: ", ")); it may be paused at a breakpoint.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The message as it travels: request or status line, headers, blank line, body.
private struct RawMessage: View {
    @Environment(RequestActions.self) private var actions
    let flow: Flow
    let side: MessageSide

    private var text: String {
        let headers: [Header], body: Data, first: String
        if side == .request {
            first = "\(flow.request.method) \(flow.request.path) \(flow.upstreamHTTPVersion ?? "HTTP/1.1")"
            headers = [Header("Host", flow.request.host)].filter { _ in flow.request.headers.value(for: "host") == nil } + flow.request.headers
            body = flow.request.body
        } else {
            let status = flow.response?.status ?? 0
            first = "\(flow.upstreamHTTPVersion ?? "HTTP/1.1") \(status) \(HTTPStatus.reason(status))"
            headers = flow.response?.headers ?? []
            body = flow.response?.body ?? Data()
        }
        let bodyText = body.isEmpty ? "" : (String(data: body.prefix(1_000_000), encoding: .utf8) ?? "<\(body.count) bytes of binary data>")
        return ([first] + headers.map { "\($0.name): \($0.value)" }).joined(separator: "\n") + "\n\n" + bodyText
    }

    var body: some View {
        let raw = text
        VStack(alignment: .trailing, spacing: 4) {
            Button("Copy Raw Message", systemImage: "doc.on.doc") { actions.copy(raw, "Raw message copied") }
                .controlSize(.small)
            SyntaxTextView(raw, language: .http, wraps: true).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
