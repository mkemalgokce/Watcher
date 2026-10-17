import ServiceManagement
import SwiftUI
import WatcherCore

/// The standard macOS Settings window (⌘,).
public struct SettingsView: View {
    public init() {}
    public var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Viewer", systemImage: "textformat") }
            ProxySettings().tabItem { Label("Proxy", systemImage: "network") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 520, height: 470)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Listening") {
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        if model.isSwitchingProxy {
                            ProgressView().controlSize(.small)
                        }
                        Label(
                            model.isRunning ? "Listening on 127.0.0.1:\(String(model.engine.boundPort ?? model.settings.port))" : model.proxyError == nil ? "Stopped" : "Failed to start",
                            systemImage: "circle.fill"
                        )
                        .labelStyle(.titleAndIcon).imageScale(.small)
                        .foregroundStyle(model.isRunning ? Palette.done : model.proxyError == nil ? Color.secondary : Palette.error)
                        Button(model.isRunning ? "Stop" : "Start") { model.toggleRunning() }.disabled(model.isSwitchingProxy)
                    }
                }
                TextField("Port", value: $model.settings.port, format: .number.grouping(.never))
                if !PortRange.isValid(model.settings.port) {
                    Label("Use a port from 1 to 65535. Ports below 1024 need administrator rights.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Palette.error)
                } else if model.settings.port < 1024 {
                    Label("Ports below 1024 need administrator rights; the proxy may fail to start.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Palette.warning)
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
                OpenAtLoginToggle()
                Toggle("Turn on the system proxy when the proxy starts", isOn: $model.settings.autoSystemProxy)
                Toggle("Hide Apple system traffic", isOn: $model.settings.hideAppleTraffic)
                Toggle("Show website icons", isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "icons.websites") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "icons.websites") }
                ))
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
}

/// macOS owns the login item, so its status is read back after every change instead of being stored in settings.
private struct OpenAtLoginToggle: View {
    @Environment(AppModel.self) private var model
    @State private var isOn = SMAppService.mainApp.status == .enabled
    var body: some View {
        Toggle("Open Watcher at login", isOn: Binding(get: { isOn }, set: { on in
            do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
            catch { model.errorMessage = "Cannot change the login item: \(error.localizedDescription). This works only in the packaged Watcher.app." }
            isOn = SMAppService.mainApp.status == .enabled
        }))
    }
}

private struct AppearanceSettings: View {
    @AppStorage("body.mode") private var mode = "Pretty"
    @AppStorage("body.wrap") private var wraps = true
    @AppStorage("body.sortKeys") private var sortKeys = false
    @AppStorage("body.fontSize") private var fontSize = 12.0

    private let sample = #"{"user":{"id":42,"name":"Ada","admin":true,"tags":["a","b"],"manager":null}}"#

    var body: some View {
        Form {
            Section("Bodies") {
                Picker("Show bodies as", selection: $mode) { Text("Pretty").tag("Pretty"); Text("Raw").tag("Raw"); Text("Hex").tag("Hex") }.pickerStyle(.segmented)
                Toggle("Wrap long lines", isOn: $wraps)
                Toggle("Sort JSON keys", isOn: $sortKeys)
                Slider(value: $fontSize, in: 9 ... 20, step: 1) { Text("Font size \(Int(fontSize))") }
            }
            Section("Preview") {
                SyntaxTextView(BodyFormatter.format(Data(sample.utf8), contentType: "application/json", sortKeys: sortKeys).text, language: .json, wraps: wraps, fontSize: fontSize)
                    .frame(height: 150)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProxySettings: View {
    @Environment(AppModel.self) private var model
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
                Button("Set Up a Device…", systemImage: "iphone.gen3") { model.show(.devices) }
                Button("Show Root Certificate in Finder", systemImage: "folder") { model.revealCertificate() }
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

enum PortRange {
    static func isValid(_ port: Int) -> Bool {
        (1 ... 65535).contains(port)
    }
}
