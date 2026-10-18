import AppKit
import SwiftUI
import WatcherCore

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
        let headers = flow.headers(side), payload = flow.body(side)
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
        flow.headers(side)
    }

    private var payload: Data {
        flow.body(side)
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
        return last.isEmpty || last == "/" ? side.rawValue : last
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try decoded.write(to: url)
            model.notices.notify("Saved \(url.lastPathComponent)", .success)
        } catch { model.notices.notify("Cannot save \(url.lastPathComponent): \(error)", .error) }
    }
}
