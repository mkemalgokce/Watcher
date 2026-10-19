import SwiftUI
import WatcherCore

/// Builds a request from scratch or from a captured one (Edit & Repeat), sends it through the proxy and shows the answer
/// with the same panel the inspector uses. State and rules live in `ComposeViewModel`.
struct ComposeView: View {
    @Environment(WindowRouter.self) private var router
    @Environment(ProxyController.self) private var proxy
    @Environment(RequestActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var viewModel: ComposeViewModel
    @FocusState private var urlFocused: Bool

    init(now: @escaping @Sendable () -> Date) {
        self.init(viewModel: ComposeViewModel(now: now))
    }

    init(viewModel: ComposeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let source = router.composeSource, viewModel.original != nil {
                editingBanner(source)
            }
            urlBar.padding(Metrics.gutter)
            Divider()
            VSplitView {
                editor.padding(Metrics.gutter).frame(maxWidth: .infinity, minHeight: 200, idealHeight: 300, maxHeight: .infinity, alignment: .topLeading)
                response.frame(maxWidth: .infinity, minHeight: 180, idealHeight: 300, maxHeight: .infinity)
            }
            Divider()
            footer.padding(.horizontal, Metrics.gutter).padding(.vertical, 10)
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 600, idealHeight: 720)
        .onAppear { viewModel.loadDraft(from: router); urlFocused = true }
    }

    // MARK: Sections

    /// Edit & Repeat: which request this started from, what has been changed, and the way back or to a comparison.
    private func editingBanner(_ source: Flow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Editing #\(source.sequence) \(source.request.method) \(source.request.path)").font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(viewModel.changesSummary)
                    .font(.caption).foregroundStyle(viewModel.hasChanges ? Palette.modified : Color.secondary)
            }
            Spacer()
            if let sent = viewModel.comparableRequest {
                Button("Compare with Original", systemImage: "arrow.left.arrow.right") {
                    actions.compareWithOriginal(source, sent: sent)
                }
                .help("Open Compare with the original response as the base")
            }
            Button("Reset to Original", systemImage: "arrow.uturn.backward") { viewModel.resetToOriginal() }
                .disabled(!viewModel.hasChanges).help("Throw away your edits")
        }
        .controlSize(.small)
        .padding(.horizontal, Metrics.gutter).padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var urlBar: some View {
        HStack(spacing: 8) {
            Picker("Method", selection: $viewModel.method) {
                ForEach(RequestMethod.common, id: \.self) { Text($0) }
            }
            .labelsHidden().fixedSize().accessibilityLabel("Method")
            TextField("https://api.example.com/path, or paste a curl command", text: $viewModel.address)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced)).focused($urlFocused)
                .onSubmit(send).accessibilityLabel("URL").help("Type a URL, or paste a whole curl command to fill in the method, headers and body.")
            Button(action: send) {
                if viewModel.isSending {
                    ProgressView().controlSize(.small).frame(width: 64).accessibilityLabel("Sending")
                } else {
                    Label(viewModel.isWebSocket ? "Connect" : "Send", systemImage: "paperplane.fill").frame(minWidth: 64)
                }
            }
            .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(viewModel.isSending)
            .help("Send (⌘↩)")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabStrip(
                items: ComposeViewModel.Tab.allCases.map { TabItem(id: $0, title: $0.rawValue, symbol: $0.symbol, badge: viewModel.badge($0)) },
                selection: $viewModel.tab
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    switch viewModel.tab {
                    case .params:
                        KeyValueEditor(rows: $viewModel.params, title: "Query parameters", textStyle: .form)
                        hint("Parameters stay in sync with the URL above.")
                    case .headers:
                        KeyValueEditor(rows: $viewModel.headers, title: "Headers", suggestions: KeyValueEditor.commonHeaders)
                        if viewModel.bodyKind != .none, viewModel.bodyKind != .binary {
                            hint("Content-Type is set from the body type unless you add your own.")
                        }
                    case .auth: authEditor
                    case .body: bodyEditor
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Label(text, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
    }

    private var authEditor: some View {
        Form {
            Picker("Type", selection: $viewModel.auth) { ForEach(ComposeViewModel.Auth.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
            switch viewModel.auth {
            case .none: Text("No Authorization header is added.").foregroundStyle(.secondary)
            case .bearer: SecureField("Token", text: $viewModel.token)
            case .basic: TextField("Username", text: $viewModel.username); SecureField("Password", text: $viewModel.password)
            }
            if viewModel.auth != .none {
                Text("Sent as an Authorization header. A header you add yourself takes precedence.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(minHeight: 160)
    }

    @ViewBuilder private var bodyEditor: some View {
        Picker("Body type", selection: $viewModel.bodyKind) { ForEach(RequestBodyBuilder.Kind.allCases) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.menu).fixedSize()
        switch viewModel.bodyKind {
        case .none:
            hint(viewModel.method == "GET" || viewModel.method == "HEAD" ? "GET and HEAD requests usually have no body." : "This request is sent without a body.")
        case .json, .text:
            SyntaxTextView(text: $viewModel.bodyText, language: viewModel.bodyKind == .json ? .json : .plain).frame(minHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius))
                .overlay(alignment: .topTrailing) {
                    if viewModel.bodyKind == .json {
                        GlassGroup {
                            HStack(spacing: 2) {
                                IconButton("Beautify JSON", symbol: "text.alignleft") { viewModel.beautifyBody() }
                                IconButton("Minify JSON", symbol: "arrow.down.right.and.arrow.up.left") {
                                    viewModel.minifyBody()
                                }
                            }
                        }
                        .padding(6)
                    }
                }
            if viewModel.isBodyInvalidJSON {
                Label("This is not valid JSON yet; it will be sent as typed.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Palette.warning)
            }
        case .form:
            KeyValueEditor(rows: $viewModel.formRows, title: "Form fields", textStyle: .form)
        case .multipart:
            KeyValueEditor(rows: $viewModel.formRows, title: "Parts", allowsFiles: true, textStyle: .form)
            hint("Use the type menu on a row to attach a file.")
        case .graphQL:
            Text("Query").font(.subheadline.weight(.medium))
            SyntaxTextView(text: $viewModel.bodyText, language: .graphql).frame(minHeight: 120).clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius))
            Text("Variables (JSON object)").font(.subheadline.weight(.medium))
            SyntaxTextView(text: $viewModel.graphQLVariables, language: .json).frame(minHeight: 60).clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius))
        case .binary:
            HStack {
                if let file = viewModel.file {
                    Label("\(file.filename) · \(Format.bytes(file.data.count))", systemImage: "doc")
                } else {
                    Text("No file chosen.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose File…") {
                    Task { await viewModel.chooseFile(using: model.filePicker) }
                }
            }
        }
    }

    @ViewBuilder private var response: some View {
        switch viewModel.phase {
        case let .received(flow):
            MessagePanel(flow: flow, side: .response)
        case .sending:
            ProgressView(viewModel.waitingText).controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Not Sent", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.error)
            } description: {
                Text(message)
            } actions: {
                if !proxy.isRunning {
                    Button("Start Proxy") { proxy.toggleRunning() }.buttonStyle(.borderedProminent)
                }
            }
        case .idle:
            ContentUnavailableView {
                Label("No Response Yet", systemImage: "paperplane")
            } description: {
                Text(proxy.isRunning ? "Press ⌘↩ to send. The answer appears here and in the request list." : "Start the proxy first: requests are sent through Watcher so your tools apply.")
                Text("Tip: paste a curl command into the address field to fill in the method, headers and body.")
            } actions: {
                if !proxy.isRunning {
                    Button("Start Proxy") { proxy.toggleRunning() }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Follow redirects", isOn: $viewModel.followRedirects)
            if let problem = viewModel.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.error).font(.callout).lineLimit(2)
            }
            Spacer()
            Button("Copy as cURL", systemImage: "terminal") { viewModel.copyAsCURL(using: actions) }
            Button("Close") { router.composeSource = nil; dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private func send() {
        Task { await viewModel.submit(using: actions, isProxyRunning: proxy.isRunning) { dismiss() } }
    }
}
