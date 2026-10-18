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
    @Environment(RequestActions.self) private var actions
    @Environment(SessionFilesViewModel.self) private var sessionFiles
    let flow: Flow
    let side: MessageSide
    @Bindable var options: ViewerOptions
    @State private var jsonPath = ""
    @State private var viewModel: BodyViewerViewModel

    private struct Key: Hashable { let flow: UUID; let side: MessageSide; let mode: BodyMode; let sortKeys: Bool; let path: String; let size: Int }

    init(
        flow: Flow, side: MessageSide, options: ViewerOptions,
        makeViewModel: @autoclosure @escaping () -> BodyViewerViewModel
    ) {
        self.flow = flow; self.side = side; self.options = options
        _viewModel = State(wrappedValue: makeViewModel())
    }

    private var prepared: BodyRendering.Prepared? {
        viewModel.prepared
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

    private var encoding: String? {
        headers.value(for: "content-encoding")
    }

    private var unpackKey: BodyRendering.UnpackKey {
        BodyRendering.UnpackKey(flow: flow.id, side: side, size: payload.count)
    }

    private var current: BodyRendering.Unpacked? {
        viewModel.current(for: flow, side: side)
    }

    private var decoded: Data {
        current?.data ?? payload
    }

    private var richKind: RichKind? {
        current?.richKind
    }

    private var effectiveMode: BodyMode {
        BodyRendering.effectiveMode(chosen: options.mode, richKind: richKind)
    }

    private var showsFilterField: Bool {
        effectiveMode != .preview && prepared?.language == .json && (options.showsJSONFilter || !jsonPath.isEmpty)
    }

    private var textMode: BodyMode {
        effectiveMode == .preview ? .pretty : effectiveMode
    }

    private var key: Key {
        Key(flow: flow.id, side: side, mode: textMode, sortKeys: options.sortsKeys, path: jsonPath, size: payload.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !payload.isEmpty {
                toolbar
            } // formats and filters mean nothing for an empty body
            if showsFilterField, let prepared {
                TextField("Filter with a JSON path or jq: users[0].name, ..email, .users[] | .id", text: $jsonPath)
                    .textFieldStyle(.roundedBorder).controlSize(.small).accessibilityLabel("JSON path or jq filter")
                if prepared.pathFailed {
                    Label("This filter matched nothing, so the whole body is shown.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.warning)
                }
            }
            content
        }
        .task(id: key) {
            await viewModel.prepare(flow, side: side, mode: textMode, sortKeys: options.sortsKeys, path: jsonPath)
        }
        .task(id: unpackKey) { await viewModel.unpack(flow, side: side) }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TabStrip(items: BodyRendering.modes(richKind: richKind).map { item in
                TabItem(id: item, title: item.rawValue, symbol: item.symbol, shortcut: "⌃⌘\((BodyMode.allCases.firstIndex(of: item) ?? 0) + 1)")
            }, selection: Binding(get: { effectiveMode }, set: { options.mode = $0 }))
            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).layoutPriority(-1)
            Spacer(minLength: 0)
            GlassGroup {
                HStack(spacing: 2) {
                    if effectiveMode != .preview, prepared?.language == .json {
                        IconButton(
                            "Filter with a JSON path or jq expression", symbol: "line.3.horizontal.decrease.circle",
                            shortcut: "⇧⌘J", isOn: options.showsJSONFilter
                        ) { options.toggleJSONFilter() }
                    }
                    if effectiveMode != .preview {
                        IconButton(
                            options.wrapsLines ? "Don't Wrap Long Lines" : "Wrap Long Lines",
                            symbol: "arrow.turn.down.left", shortcut: "⌥⌘L", isOn: options.wrapsLines
                        ) { options.toggleLineWrapping() }
                    }
                    IconButton("Copy Body", symbol: "doc.on.doc") { actions.copy(fullText(), "Body copied") }
                    Menu {
                        if prepared?.language == .json {
                            Toggle("Sort Keys", isOn: $options.sortsKeys)
                        }
                        Stepper("Font Size: \(Int(options.fontSize))", value: $options.fontSize, in: 9 ... 20)
                        Divider()
                        if prepared?.language == .json {
                            Button("Copy as Minified JSON") { actions.copy(BodyFormatter.minified(fullText(), language: .json), "Minified JSON copied") }
                        }
                        Button("Copy as Base64") { actions.copy(decoded.base64EncodedString(), "Base64 copied") }
                        OpenWithMenu(data: decoded, name: fileName, contentType: contentType)
                        Button("Save Body…", systemImage: "square.and.arrow.down") {
                            sessionFiles.saveBody(of: flow, side: side)
                        }
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
                    let shown = Format.bytes(BodyRendering.displayLimit)
                    Label(
                        "Showing the first \(shown) of \(Format.bytes(cut)). Copy or save the body to get all of it.",
                        systemImage: "scissors"
                    )
                    .font(.caption).foregroundStyle(Palette.warning)
                }
                // A hex dump is columns; wrapping would break them.
                SyntaxTextView(
                    prepared.text, language: prepared.language,
                    wraps: prepared.language == .binary ? false : options.wrapsLines, fontSize: options.fontSize
                )
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
        BodyRendering.summary(mode: effectiveMode, richKind: richKind, prepared: prepared)
    }

    private func fullText() -> String {
        viewModel.fullText(flow, side: side, mode: textMode, sortKeys: options.sortsKeys)
    }

    private var fileName: String {
        ExchangeText.suggestedFileName(for: flow, side: side)
    }
}
