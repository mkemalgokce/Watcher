import SwiftUI
import WatcherCore

/// One side of an exchange (the request or the response) with its own sections:
/// Headers, Params (request only), Body, Cookies and the Raw message.
struct MessagePanel: View {
    @Environment(AppModel.self) private var model
    let flow: Flow
    let side: MessageSide
    /// In a narrow inspector the title becomes the Request / Response switch, so switching costs no extra row.
    var switchesSide = false
    @AppStorage("panel.request.section") private var requestSection = Section.body.rawValue
    @AppStorage("panel.response.section") private var responseSection = Section.body.rawValue

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

    private var sectionBinding: Binding<String> {
        side == .request ? $requestSection : $responseSection
    }

    /// The chosen section, except that a request without a body shows its parameters (or headers) instead of an empty Body,
    /// and a section this exchange does not have (Messages on plain HTTP) falls back to Body.
    private var section: Section {
        var chosen = Section(rawValue: sectionBinding.wrappedValue) ?? .body
        if !available.contains(chosen) {
            chosen = .body
        }
        guard side == .request, chosen == .body, flow.request.body.isEmpty else { return chosen }
        return fields.isEmpty ? .headers : .params
    }

    private var headers: [Header] {
        flow.headers(side)
    }

    private var fields: [FormField] {
        side == .request ? FormFields.parse(flow.request) : []
    }

    private var cookies: [CookieEntry] {
        Cookies.entries(for: flow).filter { $0.source == (side == .request ? .request : .response) }
    }

    private var embedded: [Base64Segment] {
        EmbeddedDataIndex.shared.segments(in: flow, side: side)
    }

    private var available: [Section] {
        Section.allCases.filter { section in
            switch section {
            case .params: side == .request
            case .messages: side == .response && flow.isWebSocket
            case .previewers: side == .response && !model.settings.previewers.active.isEmpty
            case .decoded: !embedded.isEmpty
            default: true
            }
        }
    }

    private func count(_ section: Section) -> Int? {
        switch section {
        case .headers: headers.count
        case .params: fields.count
        case .cookies: cookies.count
        case .messages: flow.webSocketMessages.count
        case .decoded: embedded.count
        case .body, .raw, .previewers: nil
        }
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
                case .body: BodyViewer(flow: flow, side: side)
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
                    ], selection: $model.exchangeSide)
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
            }, selection: Binding(get: { section }, set: { sectionBinding.wrappedValue = $0.rawValue }))
                .accessibilityLabel("\(side == .request ? "Request" : "Response") section")
        }
    }

    private var detail: String {
        let body = flow.body(side)
        let type = headers.value(for: "content-type")?.split(separator: ";").first.map(String.init)
        // A response always states its size, so an empty one reads "0 B" instead of looking unloaded.
        let size = side == .response || !body.isEmpty ? Format.bytes(body.count) : nil
        return [type, size].compactMap(\.self).joined(separator: " · ")
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
    @Environment(AppModel.self) private var model
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
            Button("Copy Raw Message", systemImage: "doc.on.doc") { model.copy(raw, "Raw message copied") }.controlSize(.small)
            SyntaxTextView(raw, language: .http, wraps: true).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
