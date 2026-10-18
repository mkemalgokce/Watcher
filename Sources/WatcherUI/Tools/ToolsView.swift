import SwiftUI
import WatcherCore

/// One page per debugging tool, each saying what it does. Edits write straight into `model.settings`, which the model saves and applies live.
/// Listening, caching and other app-wide switches live in Settings (⌘,), not here.
struct ToolsView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    enum Tool: String, CaseIterable, Identifiable {
        case sslProxying = "SSL Proxying"
        case breakpoint = "Breakpoints"
        case mapLocal = "Map Local"
        case mapRemote = "Map Remote"
        case scripting = "Scripting"
        case block = "Block List"
        case allow = "Allow List"
        case throttling = "Throttling"
        case dns = "DNS Spoofing"
        case reverse = "Reverse Proxy"
        case externalProxy = "External Proxy"
        case protobuf = "Protobuf"
        case previewers = "Previewers"
        case certificates = "Certificates"
        var id: Self {
            self
        }

        var icon: String {
            switch self {
            case .sslProxying: "lock.open"
            case .block: "nosign"
            case .allow: "checkmark.shield"
            case .mapLocal: "doc.on.doc"
            case .mapRemote: "arrow.triangle.swap"
            case .breakpoint: "pause.circle"
            case .scripting: "curlybraces"
            case .throttling: "tortoise"
            case .dns: "server.rack"
            case .reverse: "arrow.uturn.left"
            case .externalProxy: "point.3.connected.trianglepath.dotted"
            case .protobuf: "shippingbox"
            case .previewers: "eye"
            case .certificates: "lock.doc"
            }
        }

        /// What the tool does and when to reach for it, shown at the top of its page.
        var explanation: String {
            switch self {
            case .sslProxying: "Which HTTPS hosts Watcher decrypts. Other hosts pass through as encrypted tunnels: you see the host name, not the content. The client must trust Watcher's certificate (⇧⌘D)."
            case .breakpoint: "Pauses matching requests or responses so you can change them before they continue. Paused traffic opens in Breakpoints (⌘B)."
            case .mapLocal: "Answers matching requests with a file from your disk instead of calling the server. Edit a JSON file to try UI states without touching the backend."
            case .mapRemote: "Sends matching requests somewhere else, for example production to staging. Empty fields keep the original value."
            case .scripting: "Runs JavaScript on matching traffic. onRequest(context, url, request) and onResponse(context, url, request, response) return the changed message."
            case .block: "Answers matching requests with 403 instead of sending them. Shows how an app copes when a service is down."
            case .allow: "Only matching requests go through; everything else is blocked. Useful to focus on one API."
            case .throttling: "Simulates a slow or lossy network for all traffic, or for one host."
            case .dns: "Resolves a host name to the address you choose, like an /etc/hosts entry that only applies to traffic through Watcher."
            case .reverse: "Listens on a local port and forwards to a server. Point a client at localhost:port to capture it without any proxy settings."
            case .externalProxy: "Sends Watcher's outgoing traffic through another proxy, such as a corporate proxy."
            case .protobuf: "Decodes protobuf bodies with your schemas so they show as named fields instead of numbers."
            case .previewers: "Adds your own inspector tab: JavaScript that turns a request into text."
            case .certificates: "Uses your own certificate for a host, or presents a client certificate to the server (mutual TLS)."
            }
        }

        static let groups: [(String, [Tool])] = [
            ("Inspect", [.sslProxying, .breakpoint, .protobuf, .previewers]),
            ("Change traffic", [.mapLocal, .mapRemote, .scripting, .block, .allow]),
            ("Network", [.throttling, .dns, .reverse, .externalProxy, .certificates]),
        ]
    }

    var body: some View {
        @Bindable var model = model
        let viewModel = viewModel
        NavigationSplitView {
            List(selection: Binding(get: { viewModel.selection }, set: { viewModel.selection = $0 })) {
                ForEach(Tool.groups, id: \.0) { title, tools in
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
    private func sidebarRow(_ tool: Tool, viewModel: ToolsViewModel) -> some View {
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
        ToolsViewModel(settings: model.settings, router: model.router, proxy: model.proxy)
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
                title: { $0.name.orElse($0.matching.pattern) },
                make: { BlockRule(matching: MatchingRule(pattern: "*")) },
                problems: problems
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
                Toggle("Hide blocked requests from the list", isOn: rule.hidesRequest)
            }
        case .allow:
            RuleListEditor(
                tool: tool,
                set: $model.settings.allowList,
                title: { $0.name.orElse($0.matching.pattern) },
                make: { AllowRule(matching: MatchingRule(pattern: "*")) },
                problems: problems
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
            }
        case .mapLocal:
            RuleListEditor(
                tool: tool,
                set: $model.settings.mapLocal,
                title: { $0.name.orElse($0.matching.pattern) },
                make: { MapLocalRule(matching: MatchingRule(pattern: "*"), source: .file("")) },
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
                title: { $0.name.orElse($0.matching.pattern) },
                make: { MapRemoteRule(matching: MatchingRule(pattern: "*"), destination: .init()) },
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
                title: { $0.name.orElse($0.matching.pattern) },
                make: { BreakpointRule(matching: MatchingRule(pattern: "*")) },
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
                title: { $0.name.orElse($0.matching.pattern) },
                make: { ScriptRule(matching: MatchingRule(pattern: "*")) },
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
                make: { DNSSpoofRule(host: "example.com", address: "127.0.0.1") },
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
                make: { ReverseProxyRule(localPort: 9191, remoteHost: "example.com") },
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
                title: { $0.name.orElse($0.matching.pattern) },
                make: { PreviewerRule(matching: MatchingRule(pattern: "*")) },
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
                make: { CustomCertificateRule(host: "api.example.com", role: .server, p12Path: "") },
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
