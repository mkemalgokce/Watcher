import SwiftUI
import WatcherCore

/// The standard macOS Settings window (⌘,).
public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    public init() {}
    public var body: some View {
        TabView {
            GeneralSettings(pane: model.settingsPane).tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings(options: model.viewer).tabItem { Label("Viewer", systemImage: "textformat") }
            ProxySettings().tabItem { Label("Proxy", systemImage: "network") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 520, height: 470)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(ProxyController.self) private var proxy
    @Bindable var pane: SettingsViewModel
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Listening") {
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        if proxy.isSwitchingProxy {
                            ProgressView().controlSize(.small)
                        }
                        Label(pane.statusText, systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon).imageScale(.small)
                            .foregroundStyle(statusTint)
                        Button(proxy.isRunning ? "Stop" : "Start") { proxy.toggleRunning() }
                            .disabled(proxy.isSwitchingProxy)
                    }
                }
                TextField("Port", value: $model.settings.port, format: .number.grouping(.never))
                if let warning = pane.portWarning {
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(warning == .invalid ? Palette.error : Palette.warning)
                }
                Toggle("Pick another port if it is taken", isOn: $model.settings.autoSelectPort)
                Toggle("Listen on all interfaces (phones, tablets)", isOn: $model.settings.listenOnAllInterfaces)
                Toggle("Also listen on IPv6", isOn: $model.settings.listenOnIPv6).disabled(!model.settings.listenOnAllInterfaces)
                Toggle("Only allow listed devices (this Mac always can)", isOn: $model.settings.accessControl.isEnabled)
                if model.settings.accessControl.isEnabled {
                    TextField(
                        "Allowed addresses",
                        text: Binding(
                            get: { model.settings.accessControl.allowedAddresses.joined(separator: ", ") },
                            set: { model.settings.accessControl.allowedAddresses = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                        ),
                        prompt: Text("192.168.1.*, 10.0.0.5")
                    )
                }
                Toggle("Also accept SOCKS5 clients", isOn: $model.settings.socks.isEnabled)
                if model.settings.socks.isEnabled {
                    TextField("SOCKS port", value: $model.settings.socks.port, format: .number.grouping(.never))
                }
            }
            Section("This Mac") {
                Toggle("Open Watcher at login", isOn: $pane.opensAtLogin)
                Toggle("Turn on the system proxy when the proxy starts", isOn: $model.settings.autoSystemProxy)
                Toggle("Hide Apple system traffic", isOn: $model.settings.hideAppleTraffic)
                Toggle("Show website icons", isOn: $pane.showsWebsiteIcons)
                Text("Icons are downloaded from each site's /favicon.ico, directly and not through Watcher, and kept in ~/.watcher/favicons.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Session") {
                Stepper("Keep at most \(model.settings.maxFlows == 0 ? "∞" : "\(model.settings.maxFlows)") requests", value: $model.settings.maxFlows, in: 0 ... 100_000, step: 500)
                Text("0 keeps everything until you clear the session.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusTint: Color {
        switch pane.status {
        case .listening: Palette.done
        case .stopped: .secondary
        case .failed: Palette.error
        }
    }
}

private struct AppearanceSettings: View {
    @Bindable var options: ViewerOptions

    private let sample = #"{"user":{"id":42,"name":"Ada","admin":true,"tags":["a","b"],"manager":null}}"#

    var body: some View {
        Form {
            Section("Bodies") {
                Picker("Show bodies as", selection: $options.mode) {
                    ForEach(BodyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("Wrap long lines", isOn: $options.wrapsLines)
                Toggle("Sort JSON keys", isOn: $options.sortsKeys)
                Slider(value: $options.fontSize, in: 9 ... 20, step: 1) { Text("Font size \(Int(options.fontSize))") }
            }
            Section("Preview") {
                let text = BodyFormatter.format(
                    Data(sample.utf8), contentType: "application/json", sortKeys: options.sortsKeys
                ).text
                SyntaxTextView(text, language: .json, wraps: options.wrapsLines, fontSize: options.fontSize)
                    .frame(height: 150)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProxySettings: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @Environment(RequestActions.self) private var actions
    var body: some View {
        @Bindable var model = model
        Form {
            Section("HTTPS") {
                Toggle("Offer HTTP/2 to clients", isOn: $model.settings.preferHTTP2)
                Toggle("Skip SSL pinning failures automatically", isOn: $model.settings.autoIgnoreSSLPinning)
                Stepper("Certificate validity: \(model.settings.leafCertificateValidityDays) days", value: $model.settings.leafCertificateValidityDays, in: 1 ... 825, step: 30)
                TextField("TLS key log file", text: $model.settings.tlsKeyLogFile, prompt: Text("Optional path for Wireshark"))
            }
            Section("Certificate") {
                Button("Set Up a Device…", systemImage: "iphone.gen3") { router.show(.devices) }
                Button("Show Root Certificate in Finder", systemImage: "folder") { actions.revealCertificate() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Repeat & Compose") {
                Toggle("Bypass caches when repeating a request", isOn: $model.settings.noCachingOnRepeat)
                Toggle("Add the proxy to copied cURL commands", isOn: $model.settings.includeProxyInCURL)
                Stepper("Compose timeout: \(model.settings.composeTimeoutSeconds) s", value: $model.settings.composeTimeoutSeconds, in: 5 ... 600, step: 5)
            }
            Section("Traffic") {
                Toggle("Mark requests changed by a tool", isOn: $model.settings.markModifiedTraffic)
                Toggle("Disable caching for all traffic", isOn: $model.settings.noCaching)
            }
            Section("MCP") {
                Toggle("Redact secrets in MCP output", isOn: $model.settings.mcpRedaction)
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
    #Preview("Settings") { SettingsView().environment(AppModel.preview()) }
#endif
