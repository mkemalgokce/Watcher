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
        // Holds no state of its own (it reads the model), so a fresh one per update is free and always current.
        let viewModel = ToolsViewModel(model: model)
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

    @ViewBuilder private var detail: some View {
        @Bindable var model = model
        let tool = router.toolsSelection
        switch tool {
        case .sslProxying:
            SSLProxyingTab(settings: $model.settings.sslProxying, tool: tool)
        case .block:
            RuleListEditor(
                tool: tool,
                set: $model.settings.blockList,
                title: { $0.name.orElse($0.matching.pattern) },
                make: { BlockRule(matching: MatchingRule(pattern: "*")) },
                problems: { ToolValidation.problems($0.matching) }
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
                problems: { ToolValidation.problems($0.matching) }
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
            }
        case .mapLocal:
            RuleListEditor(
                tool: tool,
                set: $model.settings.mapLocal,
                title: { $0.name.orElse($0.matching.pattern) },
                make: { MapLocalRule(matching: MatchingRule(pattern: "*"), source: .file("")) },
                problems: { ToolValidation.problems($0.matching) }
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
                problems: { ToolValidation.problems($0.matching) }
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
                problems: { ToolValidation.problems($0.matching) }
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
                problems: { ToolValidation.problems($0.matching) }
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
                problems: { ToolValidation.problems($0) }
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
                problems: { rule in
                    ToolValidation.problems(
                        rule,
                        proxyPort: model.proxy.port,
                        others: model.settings.reverseProxy.rules.filter { $0.localPort != rule.localPort || $0.remoteHost != rule.remoteHost }
                    )
                }
            ) { rule in
                Section {
                    TextField("Name", text: rule.name, prompt: Text("Optional"))
                    HStack {
                        Stepper("Local port: \(String(rule.wrappedValue.localPort))", value: rule.localPort, in: 1024 ... 65535)
                        Button("Suggest Free Port") {
                            if let port = model.engine.suggestReversePort() {
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
            ProtobufTab(settings: $model.settings.value, tool: tool)
        case .previewers:
            RuleListEditor(
                tool: tool,
                set: $model.settings.previewers,
                title: { $0.name.orElse($0.matching.pattern) },
                make: { PreviewerRule(matching: MatchingRule(pattern: "*")) },
                problems: { ToolValidation.problems($0.matching) }
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
                problems: { ToolValidation.problems($0) }
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

// MARK: - Shared building blocks

/// Title, what the tool does, and its master switch.
private struct ToolHeader<Accessory: View>: View {
    let tool: ToolsView.Tool
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tool.icon).font(.title2).foregroundStyle(.tint).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.rawValue).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                // No fixedSize(vertical:) here: inside the split view's detail it sends layout into a loop and the whole window draws blank.
                Text(tool.explanation).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560, alignment: .leading)
            Spacer(minLength: 8)
            accessory
        }
        .padding(16)
    }
}

extension ToolHeader where Accessory == AnyView {
    init(tool: ToolsView.Tool, isOn: Binding<Bool>) {
        self.tool = tool
        accessory = AnyView(Toggle("Turn \(tool.rawValue) on", isOn: isOn).toggleStyle(.switch).labelsHidden()
            .help(isOn.wrappedValue ? "On: rules below take effect" : "Off: rules are kept but do nothing"))
    }
}

/// Master switch, a compact list of rules on the left and the selected rule's fields on the right.
private struct RuleListEditor<Rule: ToolRule, Row: View>: View {
    let tool: ToolsView.Tool
    @Binding var set: RuleSet<Rule>
    /// One line that identifies a rule in the list.
    let title: (Rule) -> String
    let make: () -> Rule
    /// What is wrong with a rule (see ToolValidation); shown above its form and as a mark in the list.
    var problems: (Rule) -> [String] = { _ in [] }
    @ViewBuilder let row: (Binding<Rule>) -> Row
    @State private var selection: Int?

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(tool: tool, isOn: $set.isEnabled)
            if !set.isEnabled, !set.rules.isEmpty {
                HStack {
                    Label("\(tool.rawValue) is off, so these rules do nothing.", systemImage: "pause.circle")
                        .font(.callout).foregroundStyle(Palette.warning)
                    Spacer()
                    Button("Turn On") { set.isEnabled = true }.controlSize(.small)
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            Divider()
            if set.rules.isEmpty {
                ContentUnavailableView {
                    Label("No rules yet", systemImage: tool.icon)
                } description: {
                    Text("Add a rule, or right-click a request in the list for a shortcut.")
                } actions: {
                    Button("Add Rule") { add() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A fixed list beside a flexible form: HSplitView would split the space in half and push the form out of a narrow window.
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        List(selection: $selection) {
                            ForEach(set.rules.indices, id: \.self) { index in
                                ruleRow(index).tag(index)
                            }
                        }
                        .onDeleteCommand { removeSelected() }
                        Divider()
                        bottomBar
                    }
                    .frame(width: 220)
                    Divider()
                    Group {
                        if let selection, set.rules.indices.contains(selection) {
                            Form {
                                let issues = problems(set.rules[selection])
                                if !issues.isEmpty {
                                    Section {
                                        ForEach(issues, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning) }
                                    }
                                }
                                row($set.rules[selection])
                                Section {
                                    TextField("Folder", text: Binding(
                                        get: { set.rules[selection].folder ?? "" },
                                        set: { set.rules[selection].folder = $0.isEmpty ? nil : $0 }
                                    ), prompt: Text("Optional"))
                                } footer: { Text("Rules in one folder can be switched on or off together.") }
                            }
                            .formStyle(.grouped)
                        } else {
                            ContentUnavailableView("Select a rule", systemImage: "sidebar.left", description: Text("Pick a rule on the left to edit it."))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if selection == nil, !set.rules.isEmpty {
                selection = 0
            }
        }
    }

    private func ruleRow(_ index: Int) -> some View {
        let rule = set.rules[index]
        return HStack(spacing: 8) {
            // Bounds-checked: a row drawn just before a delete must not write to an index that is gone.
            Toggle("Enabled", isOn: Binding(get: { rule.isEnabled }, set: {
                on in if set.rules.indices.contains(index) {
                    set.rules[index].isEnabled = on
                }
            }))
            .toggleStyle(.checkbox).labelsHidden()
            .accessibilityLabel("Enable \(title(rule))")
            VStack(alignment: .leading, spacing: 1) {
                Text(title(rule)).lineLimit(1).truncationMode(.middle).foregroundStyle(rule.isEnabled ? .primary : .secondary)
                if let folder = rule.folder {
                    Label(folder, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !problems(rule).isEmpty {
                Spacer(minLength: 0)
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning).font(.caption)
                    .help(problems(rule).joined(separator: "\n")).accessibilityLabel("Needs attention")
            }
        }
        .contextMenu {
            Button("Duplicate") { selection = set.duplicate(at: index) }
            Button("Delete", role: .destructive) { selection = set.remove(at: index) }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 2) {
            Button("Add Rule", systemImage: "plus") { add() }.help("Add a rule")
            Button("Remove Rule", systemImage: "minus") { removeSelected() }.disabled(selection == nil).help("Remove the selected rule (⌫)")
            Spacer()
            if !set.folders.isEmpty {
                Menu("Folders", systemImage: "folder") {
                    ForEach(set.folders, id: \.self) { name in
                        Section(name) {
                            Button("Enable All in \(name)") { set.setFolder(name, enabled: true) }
                            Button("Disable All in \(name)") { set.setFolder(name, enabled: false) }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().help("Switch a whole folder of rules on or off")
            }
        }
        .labelStyle(.iconOnly).buttonStyle(.borderless).padding(6)
    }

    private func add() {
        selection = set.add(make())
    }

    private func removeSelected() {
        guard let selection else { return }
        self.selection = set.remove(at: selection)
    }
}

/// Which requests a rule applies to: the pattern up front, the rarer conditions folded away.
private struct RuleFields: View {
    @Binding var name: String
    @Binding var matching: MatchingRule
    @State private var showsMore = false

    var body: some View {
        Section {
            TextField("Name", text: $name, prompt: Text("Optional"))
            LabeledField(
                matching.mode == .regex ? "URL regex" : "URL pattern",
                prompt: "api.example.com/v1/*",
                text: $matching.pattern,
                help: matching.mode == .regex ? "Regular expression matched against the full URL." : "* matches any text, ? one character. The scheme is optional."
            )
            DisclosureGroup("More conditions", isExpanded: $showsMore) {
                Picker("Pattern type", selection: $matching.mode) {
                    Text("Wildcard").tag(MatchingRule.Mode.wildcard)
                    Text("Regex").tag(MatchingRule.Mode.regex)
                }
                Toggle("Include subpaths", isOn: $matching.includeSubpaths)
                LabeledField(
                    "Methods",
                    prompt: "GET, POST",
                    text: Binding(
                        get: { matching.methods.joined(separator: ", ") },
                        set: { matching.methods = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty } }
                    ),
                    help: "Empty matches every method."
                )
                LabeledField("App", prompt: "Google Chrome*", text: Binding(get: { matching.app ?? "" }, set: { matching.app = $0.isEmpty ? nil : $0 }))
                LabeledField("GraphQL operation", prompt: "GetUser", text: Binding(get: { matching.graphQLQueryName ?? "" }, set: { matching.graphQLQueryName = $0.isEmpty ? nil : $0 }))
            }
        } header: { Text("Applies to") }
            .onAppear { showsMore = matching.mode == .regex || !matching.methods.isEmpty || matching.app != nil || matching.graphQLQueryName != nil }
    }
}

/// A text field with an example as its prompt and, when it needs one, a line of help below.
private struct LabeledField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var help: String?

    init(_ label: String, prompt: String, text: Binding<String>, help: String? = nil) {
        self.label = label; self.prompt = prompt; _text = text; self.help = help
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(label, text: $text, prompt: Text(prompt))
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct OptionalText: View {
    let label: String
    let prompt: String
    @Binding var value: String?

    init(_ label: String, prompt: String, value: Binding<String?>) {
        self.label = label; self.prompt = prompt; _value = value
    }

    var body: some View {
        TextField(label, text: Binding(get: { value ?? "" }, set: { value = $0.isEmpty ? nil : $0 }), prompt: Text(prompt))
    }
}

/// Monospaced multi-line code with a visible label for VoiceOver.
private struct CodeEditorField: View {
    @Binding var text: String
    let label: String
    var minHeight: CGFloat = 140

    var body: some View {
        TextEditor(text: $text).font(.system(.callout, design: .monospaced))
            .frame(minHeight: minHeight).scrollContentBackground(.hidden)
            .padding(4).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(label)
    }
}

private struct MapLocalSourceFields: View {
    @Binding var source: MapLocalRule.Source
    @Environment(\.filePanels) private var filePanels

    private var isDirectory: Bool {
        if case .directory = source {
            true
        } else {
            false
        }
    }

    private var path: String {
        switch source { case let .file(path), let .directory(path): path }
    }

    var body: some View {
        Picker("Source", selection: Binding(get: { isDirectory }, set: { source = $0 ? .directory(path) : .file(path) })) {
            Text("File").tag(false)
            Text("Directory").tag(true)
        }.pickerStyle(.segmented)
        HStack {
            LabeledField(
                isDirectory ? "Directory" : "File",
                prompt: isDirectory ? "~/mocks/api" : "~/mocks/users.json",
                text: Binding(get: { path }, set: { source = isDirectory ? .directory($0) : .file($0) }),
                help: isDirectory ? "The request path is looked up inside this directory." : "A body file, or a full HTTP message (status line, headers, blank line, body)."
            )
            Button("Choose…") { choose() }
        }
    }

    private func choose() {
        guard let url = filePanels.chooseItem(directory: isDirectory) else { return }
        source = isDirectory ? .directory(url.path) : .file(url.path)
    }
}

/// Comma-separated text for a list of host patterns.
private func commaList(_ values: Binding<[String]>) -> Binding<String> {
    Binding(
        get: { values.wrappedValue.joined(separator: ", ") },
        set: { values.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    )
}

// MARK: - Single-purpose pages

private struct SSLProxyingTab: View {
    @Environment(WindowRouter.self) private var router
    @Environment(RequestActions.self) private var actions
    @Environment(DevicesViewModel.self) private var devices
    @Binding var settings: SSLProxyingSettings
    let tool: ToolsView.Tool

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(tool: tool) { EmptyView() }
            Divider()
            Form {
                Section {
                    LabeledField(
                        "Decrypt",
                        prompt: "*, or api.example.com, *.example.org",
                        text: commaList($settings.include),
                        help: "Comma separated. * decrypts every host."
                    )
                    LabeledField(
                        "Never decrypt",
                        prompt: "bank.example.com",
                        text: commaList($settings.exclude),
                        help: "Wins over Decrypt. Apps that pin their certificate need to be listed here to keep working."
                    )
                }
                Section("Certificate") {
                    HStack {
                        Button("Trust on This Mac…") { Task { await devices.trustOnMac() } }
                        Button("Set Up a Device…") { router.show(.devices) }
                        Button("Show in Finder") { actions.revealCertificate() }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct ThrottleTab: View {
    @Binding var throttle: ThrottleSettings
    let tool: ToolsView.Tool

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(tool: tool, isOn: $throttle.isEnabled)
            Divider()
            Form {
                Section("Profile") {
                    Picker("Profile", selection: Binding(get: { throttle.profile.name }, set: { name in
                        if let profile = throttle.availableProfiles.first(where: { $0.name == name }) {
                            throttle.profile = profile
                        }
                    })) {
                        ForEach(throttle.availableProfiles, id: \.name) { Text($0.name).tag($0.name) }
                        if !throttle.availableProfiles.contains(where: { $0.name == throttle.profile.name }) {
                            Text(throttle.profile.name).tag(throttle.profile.name)
                        }
                    }
                    Stepper("Download: \(throttle.profile.downloadKbps == 0 ? "unlimited" : "\(String(throttle.profile.downloadKbps)) kbps")", value: $throttle.profile.downloadKbps, in: 0 ... 100_000, step: 50)
                    Stepper("Upload: \(throttle.profile.uploadKbps == 0 ? "unlimited" : "\(String(throttle.profile.uploadKbps)) kbps")", value: $throttle.profile.uploadKbps, in: 0 ... 100_000, step: 50)
                    Stepper("Latency: \(String(throttle.profile.latencyMilliseconds)) ms", value: $throttle.profile.latencyMilliseconds, in: 0 ... 10000, step: 50)
                    Stepper("Packet loss: \(String(throttle.profile.packetLossPercent))%", value: $throttle.profile.packetLossPercent, in: 0 ... 100, step: 5)
                }
                Section {
                    LabeledField("Only host", prompt: "api.example.com:443", text: $throttle.host, help: "Empty slows down all traffic.")
                }
                Section("Custom profiles") {
                    TextField("Profile name", text: $throttle.profile.name)
                    HStack {
                        Button("Save as Custom Profile") { throttle.saveCurrentProfile() }
                        if throttle.customProfiles.contains(where: { $0.name == throttle.profile.name }) {
                            Button("Delete Profile", role: .destructive) { throttle.deleteCustomProfile(named: throttle.profile.name) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct ExternalProxyTab: View {
    @Binding var proxy: ExternalProxySettings
    let tool: ToolsView.Tool

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(tool: tool, isOn: $proxy.isEnabled)
            Divider()
            Form {
                Section {
                    Picker("Type", selection: $proxy.kind) {
                        Text("HTTP").tag(ExternalProxySettings.Kind.http)
                        Text("SOCKS").tag(ExternalProxySettings.Kind.socks)
                        Text("PAC file").tag(ExternalProxySettings.Kind.pac)
                    }.pickerStyle(.segmented)
                    if proxy.kind == .pac {
                        LabeledField("PAC URL", prompt: "http://proxy.example.com/proxy.pac", text: $proxy.pacURL)
                    } else {
                        LabeledField("Host", prompt: "proxy.example.com", text: $proxy.host)
                        Stepper("Port: \(String(proxy.port))", value: $proxy.port, in: 1 ... 65535)
                        TextField("Username", text: $proxy.username, prompt: Text("Optional"))
                        SecureField("Password", text: $proxy.password)
                    }
                }
                Section {
                    LabeledField("Bypass", prompt: "localhost, *.internal", text: commaList($proxy.bypass), help: "Hosts reached directly, comma separated.")
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct ProtobufTab: View {
    @Binding var settings: WatcherSettings
    let tool: ToolsView.Tool

    var body: some View {
        VStack(spacing: 0) {
            RuleListEditor(
                tool: tool,
                set: $settings.protobuf,
                title: { $0.name.orElse($0.matching.pattern) },
                make: { ProtobufRule(matching: MatchingRule(pattern: "*")) },
                problems: { ToolValidation.problems($0.matching) }
            ) { rule in
                RuleFields(name: rule.name, matching: rule.matching)
                Section("Message types") {
                    LabeledField("Request", prompt: "demo.GetUserRequest", text: rule.requestType)
                    LabeledField("Response", prompt: "demo.User", text: rule.responseType)
                }
            }
            Divider()
            Form {
                Section {
                    CodeEditorField(
                        text: Binding(
                            get: { settings.protobufSchemas.joined(separator: "\n") },
                            set: { settings.protobufSchemas = $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                        ),
                        label: "Schema files",
                        minHeight: 50
                    )
                } header: { Text("Schema files") } footer: { Text("One .desc path per line, made with protoc --descriptor_set_out.") }
            }
            .formStyle(.grouped).frame(height: 170)
        }
    }
}

private extension String {
    /// The string itself, or `fallback` when it is empty.
    func orElse(_ fallback: String) -> String {
        isEmpty ? fallback : self
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
