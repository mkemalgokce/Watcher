import SwiftUI
import WatcherCore

/// One page per debugging tool, each saying what it does. Edits write straight into `model.settings`, which the model saves and applies live.
/// Listening, caching and other app-wide switches live in Settings (⌘,), not here.
struct ToolsView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        let viewModel = viewModel
        NavigationSplitView {
            List(selection: Binding(get: { viewModel.selection }, set: { viewModel.selection = $0 })) {
                ForEach(ToolPage.groups, id: \.0) { title, tools in
                    Section(title) { ForEach(tools) { sidebarRow($0, viewModel: viewModel) } }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                detail.id(router.toolsSelection)
                Divider()
                HStack {
                    Text("Changes apply right away.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
                .padding(10)
            }
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 520, idealHeight: 640)
    }

    /// A warning mark when a rule cannot work, otherwise how many rules take effect.
    private func sidebarRow(_ tool: ToolPage, viewModel: ToolsViewModel) -> some View {
        let count = viewModel.activeCount(tool)
        let hasProblems = !viewModel.problems(tool).isEmpty
        return Label {
            Text(tool.rawValue)
        } icon: {
            SidebarIcon(
                symbol: hasProblems ? "exclamationmark.triangle.fill" : tool.icon,
                tint: hasProblems ? Palette.warning : .accentColor
            )
        }
        .tag(tool)
        .badge(count)
        .help(viewModel.summary(tool))
        .accessibilityValue(viewModel.summary(tool))
    }

    /// Holds no state of its own (it reads the model), so a fresh one per update is free and always current.
    private var viewModel: ToolsViewModel {
        model.toolsViewModel()
    }

    @ViewBuilder private var detail: some View {
        @Bindable var model = model
        let tool = router.toolsSelection
        let problems = { [viewModel] in viewModel.problems(tool, ruleAt: $0) }
        switch tool {
        case .sslProxying:
            SSLProxyingTab(settings: $model.settings.sslProxying, tool: tool)
        case .block:
            RuleListEditor(
                tool: tool,
                set: $model.settings.blockList,
                title: \.displayName,
                make: NewRule.block,
                problems: problems
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
                Toggle("Hide blocked requests from the list", isOn: rule.hidesRequest)
            }
        case .allow:
            RuleListEditor(
                tool: tool,
                set: $model.settings.allowList,
                title: \.displayName,
                make: NewRule.allow,
                problems: problems
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
            }
        case .mapLocal:
            RuleListEditor(
                tool: tool,
                set: $model.settings.mapLocal,
                title: \.displayName,
                make: NewRule.mapLocal,
                problems: problems
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
                Section("Answer with") {
                    MapLocalSourceFields(source: rule.source)
                    Stepper("Delay: \(String(rule.wrappedValue.delayMilliseconds)) ms", value: rule.delayMilliseconds, in: 0 ... 30000, step: 100)
                }
            }
        case .mapRemote:
            RuleListEditor(
                tool: tool,
                set: $model.settings.mapRemote,
                title: \.displayName,
                make: NewRule.mapRemote,
                problems: problems
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
                Section {
                    OptionalText("Scheme", prompt: "https", value: rule.destination.scheme)
                    OptionalText("Host", prompt: "staging.example.com", value: rule.destination.host)
                    OptionalText("Path", prompt: "/v2/users", value: rule.destination.path)
                    OptionalText("Query", prompt: "debug=1", value: rule.destination.query)
                } header: { Text("Send to") } footer: { Text("Leave a field empty to keep it as it was.") }
            }
        case .breakpoint:
            RuleListEditor(
                tool: tool,
                set: $model.settings.breakpoints,
                title: \.displayName,
                make: NewRule.breakpoint,
                problems: problems
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
                Section("Pause") {
                    Toggle("Before the request is sent", isOn: rule.onRequest)
                    Toggle("Before the response reaches the app", isOn: rule.onResponse)
                }
            }
        case .scripting:
            RuleListEditor(
                tool: tool,
                set: $model.settings.scripting,
                title: \.displayName,
                make: NewRule.scripting,
                problems: problems
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
                Section("Script") {
                    CodeEditorField(text: rule.source, label: "JavaScript", minHeight: 180)
                }
            }
        case .throttling:
            ThrottleTab(throttle: $model.settings.throttle, tool: tool)
        case .dns:
            RuleListEditor(
                tool: tool,
                set: $model.settings.dnsSpoofing,
                title: { "\($0.host) → \($0.address)" },
                make: NewRule.dns,
                problems: problems
            ) { rule in
                Section {
                    LabeledField("Host", prompt: "api.example.com", text: rule.host, help: "Exact host name, no wildcards.")
                    LabeledField("Address", prompt: "127.0.0.1", text: rule.address, help: "IPv4 or IPv6 address to connect to instead.")
                }
            }
        case .reverse:
            RuleListEditor(
                tool: tool,
                set: $model.settings.reverseProxy,
                title: { "localhost:\(String($0.localPort)) → \($0.remoteHost)" },
                make: NewRule.reverseProxy,
                problems: problems
            ) { rule in
                Section {
                    TextField("Name", text: rule.name, prompt: Text("Optional"))
                    HStack {
                        Stepper("Local port: \(String(rule.wrappedValue.localPort))", value: rule.localPort, in: 1024 ... 65535)
                        Button("Suggest Free Port") {
                            if let port = model.settings.suggestReversePort() {
                                rule.wrappedValue.localPort = port
                            }
                        }
                    }
                    LabeledField("Remote host", prompt: "api.example.com", text: rule.remoteHost)
                    Stepper("Remote port: \(String(rule.wrappedValue.remotePort))", value: rule.remotePort, in: 1 ... 65535)
                    Toggle("Connect to the server with TLS", isOn: rule.forceTLS)
                    Toggle("Keep the client's Host header", isOn: rule.preserveHost)
                }
            }
        case .externalProxy:
            ExternalProxyTab(proxy: $model.settings.externalProxy, tool: tool)
        case .protobuf:
            ProtobufTab(settings: $model.settings.value, tool: tool, problems: problems)
        case .previewers:
            RuleListEditor(
                tool: tool,
                set: $model.settings.previewers,
                title: \.displayName,
                make: NewRule.previewer,
                problems: problems
            ) { rule in
                Section {
                    LabeledField("Tab name", prompt: "Decoded token", text: rule.name)
                    LabeledField("URL pattern", prompt: "api.example.com/*", text: rule.matching.pattern, help: "* matches any text, ? one character.")
                    CodeEditorField(text: rule.source, label: "JavaScript", minHeight: 140)
                }
            }
        case .certificates:
            RuleListEditor(
                tool: tool,
                set: $model.settings.customCertificates,
                title: { $0.host },
                make: NewRule.certificate,
                problems: problems
            ) { rule in
                Section {
                    LabeledField("Host pattern", prompt: "*.example.com", text: rule.host)
                    Picker("Use for", selection: rule.role) {
                        Text("The client (server certificate)").tag(CustomCertificateRule.Role.server)
                        Text("The server (client certificate, mTLS)").tag(CustomCertificateRule.Role.client)
                    }
                    LabeledField(".p12 file", prompt: "~/certs/client.p12", text: rule.p12Path)
                    SecureField("Passphrase", text: rule.passphrase)
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Tools") {
        let model = AppModel.preview()
        model.settings.mapLocal = RuleSet(isEnabled: true, rules: [
            MapLocalRule(name: "Users fixture", matching: MatchingRule(pattern: "api.example.com/v1/users*"), source: .file("~/mocks/users.json")),
            MapLocalRule(matching: MatchingRule(pattern: "*/config.json"), source: .file("~/mocks/config.json")),
        ])
        model.router.toolsSelection = .sslProxying
        return ToolsView().environment(model)
    }
#endif
