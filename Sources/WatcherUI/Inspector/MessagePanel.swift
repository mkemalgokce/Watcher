import AppKit
import SwiftUI
import WatcherCore

/// Which half of an exchange a panel shows.
enum MessageSide: String, CaseIterable { case request, response }

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
        side == .request ? flow.request.headers : flow.response?.headers ?? []
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

    private var isWebSocket: Bool {
        !flow.webSocketMessages.isEmpty || flow.response?.status == 101
    }

    private var available: [Section] {
        Section.allCases.filter { section in
            switch section {
            case .params: side == .request
            case .messages: side == .response && isWebSocket
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
        let body = side == .request ? flow.request.body : flow.response?.body ?? Data()
        let type = headers.value(for: "content-type")?.split(separator: ";").first.map(String.init)
        // A response always states its size, so an empty one reads "0 B" instead of looking unloaded.
        let size = side == .response || !body.isEmpty ? Format.bytes(body.count) : nil
        return [type, size].compactMap(\.self).joined(separator: " · ")
    }
}

/// Coloured symbol, plain-coloured title.
struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon; configuration.title.foregroundStyle(.primary) }
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

enum BodyMode: String, CaseIterable {
    case preview = "Preview", pretty = "Pretty", raw = "Raw", hex = "Hex"
    var symbol: String {
        switch self { case .preview: "eye"; case .pretty: "curlybraces"; case .raw: "text.quote"; case .hex: "number" }
    }
}

/// The body of one side: rendered (image, HTML, PDF, media, events), pretty-printed with colours, raw, or hex.
struct BodyViewer: View {
    @Environment(AppModel.self) private var model
    let flow: Flow
    let side: MessageSide
    @AppStorage("body.mode") private var mode = BodyMode.preview.rawValue
    @AppStorage("body.wrap") private var wraps = true
    @AppStorage("body.sortKeys") private var sortKeys = false
    @AppStorage("body.fontSize") private var fontSize = 12.0
    /// The JSON path / jq field stays hidden until asked for (⇧⌘J), keeping one control row less above every body.
    @AppStorage("body.jsonFilter") private var showsFilter = false
    @State private var jsonPath = ""
    @State private var prepared: Prepared?
    /// The body after Content-Encoding is undone, and what it can be rendered as. Decoding a large gzip body is not cheap,
    /// so it happens once per body (off the main thread when large) instead of on every view update.
    @State private var unpacked: Unpacked?

    struct Unpacked: Equatable {
        let id: UnpackKey
        let data: Data
        let richKind: RichKind?
    }

    struct UnpackKey: Hashable { let flow: UUID; let side: MessageSide; let size: Int }

    /// Bodies below this are formatted on the spot so the first frame already shows them.
    private static let instantLimit = 256 * 1024
    /// Text longer than this is shown cut off; the whole body can still be saved or copied from the menu.
    private static let displayLimit = 16 * 1024 * 1024

    struct Prepared: Equatable {
        var text: String
        var language: BodyLanguage
        var note: String?
        var cutFrom: Int?
        var pathFailed = false
    }

    private struct Key: Hashable { let flow: UUID; let side: MessageSide; let mode: BodyMode; let sortKeys: Bool; let path: String; let size: Int }

    init(flow: Flow, side: MessageSide) {
        self.flow = flow; self.side = side
        let headers = side == .response ? flow.response?.headers ?? [] : flow.request.headers
        let payload = side == .response ? flow.response?.body ?? Data() : flow.request.body
        if payload.count < Self.instantLimit {
            let defaults = UserDefaults.standard
            var mode = BodyMode(rawValue: defaults.string(forKey: "body.mode") ?? "") ?? .preview
            if mode == .preview {
                mode = .pretty
            } // text is prepared as pretty; a rich preview does not need it
            _prepared = State(initialValue: Self.compute(
                payload,
                headers.value(for: "content-type"),
                headers.value(for: "content-encoding"),
                mode,
                defaults.bool(forKey: "body.sortKeys"),
                ""
            ))
            _unpacked = State(initialValue: Self.unpack(
                UnpackKey(flow: flow.id, side: side, size: payload.count),
                payload,
                headers.value(for: "content-type"),
                headers.value(for: "content-encoding")
            ))
        }
    }

    private var headers: [Header] {
        side == .response ? flow.response?.headers ?? [] : flow.request.headers
    }

    private var payload: Data {
        side == .response ? flow.response?.body ?? Data() : flow.request.body
    }

    private var contentType: String? {
        headers.value(for: "content-type")
    }

    private var unpackKey: UnpackKey {
        UnpackKey(flow: flow.id, side: side, size: payload.count)
    }

    private var current: Unpacked? {
        unpacked?.id == unpackKey ? unpacked : nil
    }

    private var decoded: Data {
        current?.data ?? payload
    }

    private var richKind: RichKind? {
        current?.richKind
    }

    private nonisolated static func unpack(_ key: UnpackKey, _ payload: Data, _ type: String?, _ encoding: String?) -> Unpacked {
        let data = BodyDecoder.decode(payload, contentEncoding: encoding).data
        return Unpacked(id: key, data: data, richKind: payload.isEmpty ? nil : RichKind.of(contentType: type, data: data))
    }

    /// The chosen mode, falling back to Pretty when this body has nothing to render.
    private var effectiveMode: BodyMode {
        let chosen = BodyMode(rawValue: mode) ?? .preview
        return chosen == .preview && richKind == nil ? .pretty : chosen
    }

    private var textMode: BodyMode {
        effectiveMode == .preview ? .pretty : effectiveMode
    }

    private var key: Key {
        Key(flow: flow.id, side: side, mode: textMode, sortKeys: sortKeys, path: jsonPath, size: payload.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !payload.isEmpty {
                toolbar
            } // formats and filters mean nothing for an empty body
            if effectiveMode != .preview, let prepared, prepared.language == .json, showsFilter || !jsonPath.isEmpty {
                TextField("Filter with a JSON path or jq: users[0].name, ..email, .users[] | .id", text: $jsonPath)
                    .textFieldStyle(.roundedBorder).controlSize(.small).accessibilityLabel("JSON path or jq filter")
                if prepared.pathFailed {
                    Label("This filter matched nothing, so the whole body is shown.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.warning)
                }
            }
            content
        }
        .task(id: key) { await prepare() }
        .task(id: unpackKey) {
            guard current == nil else { return }
            let (key, payload, type, encoding) = (unpackKey, payload, contentType, headers.value(for: "content-encoding"))
            let result = payload.count < Self.instantLimit ? Self.unpack(key, payload, type, encoding)
                : await Task.detached(priority: .userInitiated) { Self.unpack(key, payload, type, encoding) }.value
            if !Task.isCancelled {
                unpacked = result
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TabStrip(items: BodyMode.allCases.filter { $0 != .preview || richKind != nil }.map { item in
                TabItem(id: item, title: item.rawValue, symbol: item.symbol, shortcut: "⌃⌘\((BodyMode.allCases.firstIndex(of: item) ?? 0) + 1)")
            }, selection: Binding(get: { effectiveMode }, set: { mode = $0.rawValue }))
            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).layoutPriority(-1)
            Spacer(minLength: 0)
            GlassGroup {
                HStack(spacing: 2) {
                    if effectiveMode != .preview, prepared?.language == .json {
                        IconButton("Filter with a JSON path or jq expression", symbol: "line.3.horizontal.decrease.circle", shortcut: "⇧⌘J", isOn: showsFilter) { showsFilter.toggle() }
                    }
                    if effectiveMode != .preview {
                        IconButton(wraps ? "Don't Wrap Long Lines" : "Wrap Long Lines", symbol: "arrow.turn.down.left", shortcut: "⌥⌘L", isOn: wraps) { wraps.toggle() }
                    }
                    IconButton("Copy Body", symbol: "doc.on.doc") { model.copy(fullText(), "Body copied") }
                    Menu {
                        if prepared?.language == .json {
                            Toggle("Sort Keys", isOn: $sortKeys)
                        }
                        Stepper("Font Size: \(Int(fontSize))", value: $fontSize, in: 9 ... 20)
                        Divider()
                        if prepared?.language == .json {
                            Button("Copy as Minified JSON") { model.copy(BodyFormatter.minified(fullText(), language: .json), "Minified JSON copied") }
                        }
                        Button("Copy as Base64") { model.copy(decoded.base64EncodedString(), "Base64 copied") }
                        OpenWithMenu(data: decoded, name: fileName, contentType: contentType)
                        Button("Save Body…", systemImage: "square.and.arrow.down") { save() }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .regular)).frame(width: Metrics.iconButton, height: Metrics.iconButton)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More body actions: sort keys, font size, copy, open with, save")
                    .accessibilityLabel("More body actions")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if payload.isEmpty {
            ContentUnavailableView("No body", systemImage: "doc", description: Text(side == .response ? "The server sent no content." : "This request has no body."))
        } else if effectiveMode == .preview, let richKind {
            RichPreview(kind: richKind, data: decoded, contentType: contentType)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        } else if let prepared {
            VStack(alignment: .leading, spacing: 4) {
                if let cut = prepared.cutFrom {
                    Label("Showing the first \(Format.bytes(Self.displayLimit)) of \(Format.bytes(cut)). Copy or save the body to get all of it.", systemImage: "scissors")
                        .font(.caption).foregroundStyle(Palette.warning)
                }
                // A hex dump is columns; wrapping would break them.
                SyntaxTextView(prepared.text, language: prepared.language, wraps: prepared.language == .binary ? false : wraps, fontSize: fontSize)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        } else if payload.count > 512 * 1024 {
            ProgressView("Formatting \(Format.bytes(payload.count))…").controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear // small bodies are ready within a frame; a spinner would only flicker
        }
    }

    private var summary: String {
        if effectiveMode == .preview, let richKind {
            return switch richKind {
            case .image: "Image"; case .html: "HTML, rendered offline"; case .pdf: "PDF"; case .media: "Audio / video"
            case .eventStream: "Server-Sent Events"; case .form: "Form fields"
            }
        }
        var parts = [prepared?.language.displayName ?? "…"]
        if let note = prepared?.note {
            parts.append(note)
        }
        return parts.joined(separator: " · ")
    }

    /// Formatting and filtering run off the main thread for large bodies; a newer request (another selection, a key typed) cancels this one.
    private func prepare() async {
        let (payload, type, encoding, mode, sortKeys, path) = (payload, contentType, headers.value(for: "content-encoding"), textMode, sortKeys, jsonPath)
        var result: Prepared
        if payload.count < Self.instantLimit {
            result = Self.compute(payload, type, encoding, mode, sortKeys, path)
        } else {
            if !path.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
            } // let typing settle before querying a large document
            guard !Task.isCancelled else { return }
            result = await Task.detached(priority: .userInitiated) { Self.compute(payload, type, encoding, mode, sortKeys, path) }.value
        }
        guard !Task.isCancelled else { return }
        if result.language == .protobuf, mode == .pretty {
            result.text = model.engine.bodyText(of: flow, response: side == .response)
        }
        prepared = result
    }

    private nonisolated static func compute(_ payload: Data, _ type: String?, _ encoding: String?, _ mode: BodyMode, _ sortKeys: Bool, _ path: String, capped: Bool = true) -> Prepared {
        var result: Prepared
        switch mode {
        case .hex: result = Prepared(text: BodyFormatter.hexDump(payload), language: .binary)
        case .raw:
            result = Prepared(text: String(data: payload, encoding: .utf8) ?? BodyFormatter.hexDump(payload), language: BodyLanguage.detect(contentType: type, data: payload), note: "raw")
        case .pretty, .preview:
            let formatted = BodyFormatter.format(payload, contentType: type, contentEncoding: encoding, sortKeys: sortKeys)
            result = Prepared(text: formatted.text, language: formatted.language, note: formatted.note)
        }
        if result.language == .json, !path.isEmpty {
            let filtered = JQ.looksLikeJQ(path) ? JQ.run(path, on: payload) : JSONQuery.run(path, on: payload)
            if let filtered {
                result.text = filtered
            } else {
                result.pathFailed = true
            }
        }
        if capped, result.text.utf8.count > displayLimit {
            result.cutFrom = result.text.utf8.count
            var cut = String(decoding: result.text.utf8.prefix(displayLimit), as: UTF8.self)
            if let newline = cut.lastIndex(of: "\n") {
                cut = String(cut[..<newline])
            } // end on a whole line
            result.text = cut
        }
        return result
    }

    /// The complete text for copy and save, even when the viewer shows only the first part.
    private func fullText() -> String {
        Self.compute(payload, contentType, headers.value(for: "content-encoding"), textMode, sortKeys, "", capped: false).text
    }

    /// The last path component when it looks like a file name, otherwise "body"; the extension comes from the content type.
    private var fileName: String {
        let last = URL(string: flow.request.url)?.lastPathComponent ?? ""
        return last.isEmpty || last == "/" ? (side == .request ? "request" : "response") : last
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try decoded.write(to: url); model.notify("Saved \(url.lastPathComponent)", .success) }
        catch { model.errorMessage = "Cannot save \(url.lastPathComponent): \(error)" }
    }
}
