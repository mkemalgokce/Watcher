import SwiftUI
import WatcherCore

struct SSLProxyingTab: View {
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

struct ThrottleTab: View {
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

struct ExternalProxyTab: View {
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

struct ProtobufTab: View {
    @Binding var settings: WatcherSettings
    let tool: ToolsView.Tool
    let problems: (Int) -> [String]

    var body: some View {
        VStack(spacing: 0) {
            RuleListEditor(
                tool: tool,
                set: $settings.protobuf,
                title: { $0.name.orElse($0.matching.pattern) },
                make: { ProtobufRule(matching: MatchingRule(pattern: "*")) },
                problems: problems
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

extension String {
    /// The string itself, or `fallback` when it is empty.
    func orElse(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
