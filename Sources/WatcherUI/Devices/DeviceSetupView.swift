import CoreImage.CIFilterBuiltins
import SwiftUI
import WatcherCore

/// One place for every way of getting the root certificate onto a client: this Mac, iOS Simulators, real iPhones/iPads and Android.
struct DeviceSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var target: Target

    init(target: Target = .mac) {
        _target = State(initialValue: target)
    }

    enum Target: String, CaseIterable, Identifiable {
        case mac = "This Mac", simulator = "iOS Simulator", iPhone = "iPhone / iPad", android = "Android"
        var id: Self {
            self
        }

        var icon: String {
            switch self { case .mac: "laptopcomputer"; case .simulator: "ipad.and.iphone"; case .iPhone: "iphone.gen3"; case .android: "smartphone" }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Target.allCases, selection: $target) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch target {
                    case .mac: MacPane()
                    case .simulator: SimulatorPane()
                    case .iPhone: IPhonePane()
                    case .android: AndroidPane()
                    }
                    Spacer(minLength: 0)
                    DeviceStatusLabel()
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 640, idealWidth: 780, minHeight: 480, idealHeight: 580)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) } }
        .task { await model.devices.refresh() }
    }
}

/// Outcome of the last device action: in progress, done, or failed.
struct DeviceStatusLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let status = model.devices.status {
            HStack(spacing: 6) {
                switch status {
                case .working: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.done)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.error)
                }
                Text(status.text).textSelection(.enabled)
                    .foregroundStyle({
                        if case .failed = status {
                            Palette.error
                        } else {
                            Color.secondary
                        }
                    }())
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct Heading: View {
    let title: String, detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.title2.bold()); Text(detail).foregroundStyle(.secondary) }
    }
}

private struct Step: View {
    let number: Int, text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)").font(.caption.bold()).frame(width: 18, height: 18).background(Color.accentColor.opacity(0.2), in: Circle())
            Text(text)
        }
    }
}

private struct MacPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Heading(title: "This Mac", detail: "Trust the Watcher root certificate so Safari, Chrome and other Mac apps accept decrypted HTTPS.")
        Card {
            HStack(spacing: 12) {
                Image(systemName: model.devices.macTrusted ? "checkmark.seal.fill" : "exclamationmark.shield.fill").font(.system(size: 28))
                    .foregroundStyle(model.devices.macTrusted ? Palette.done : Palette.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.devices.macTrusted ? "Trusted" : "Not trusted yet").font(.headline)
                    Text(model.devices.macTrusted ? "The certificate is in your login keychain. HTTPS from Mac apps can be read."
                        : "Without it, HTTPS from this Mac passes through encrypted.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.devices.macTrusted {
                    Button("Remove", systemImage: "trash", role: .destructive) { Task { await model.devices.removeMacTrust() } }
                } else {
                    Button("Install & Trust…", systemImage: "lock.shield") { Task { await model.devices.trustOnMac() } }.buttonStyle(.borderedProminent)
                }
            }
        }
        HStack {
            Button("Show Certificate in Finder", systemImage: "folder") { model.revealCertificate() }
            Spacer()
        }
        Text("macOS asks for your password to change trust settings. Firefox keeps its own certificate store and needs the file imported by hand.").font(.caption).foregroundStyle(.secondary)
    }
}

private struct SimulatorPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Heading(title: "iOS Simulator", detail: "Installs the root certificate into a simulator's keychain with simctl. Restart apps that were already running.")
        if model.devices.simulators.isEmpty, model.devices.isScanning {
            ProgressView("Looking for simulators…").controlSize(.small).frame(maxWidth: .infinity, minHeight: 120)
        } else if model.devices.simulators.isEmpty {
            ContentUnavailableView(
                "No simulators found",
                systemImage: "iphone.slash",
                description: Text("Install Xcode and create a simulator, then reopen this window.")
            )
        } else {
            List(model.devices.simulators) { simulator in
                HStack {
                    Image(systemName: simulator.isBooted ? "circle.fill" : "circle").foregroundStyle(simulator.isBooted ? Palette.done : .secondary).font(.caption)
                        .accessibilityLabel(simulator.isBooted ? "Running" : "Shut down")
                    VStack(alignment: .leading) { Text(simulator.name); Text(simulator.runtime).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Install Certificate") { Task { await model.devices.install(on: simulator) } }
                }
            }
            .frame(minHeight: 200)
        }
        Text("Simulators use the Mac's network, so the system proxy setting is all they need: turn on System Proxy in the toolbar menu.").font(.caption).foregroundStyle(.secondary)
    }
}

private struct IPhonePane: View {
    @Environment(AppModel.self) private var model

    private var pageURL: String {
        "http://watcher.cert"
    }

    private var directURL: String? {
        model.lanProxyAddress.map { "http://\($0)" }
    }

    var body: some View {
        Heading(title: "iPhone / iPad", detail: "Join the same Wi-Fi as this Mac, set the proxy, then open the certificate page on the device.")
        if !model.settings.listenOnAllInterfaces {
            Label("Watcher only listens on this Mac. Turn on “Listen on all interfaces” in Settings → General so the device can connect.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
            Button("Turn On") { model.settings.listenOnAllInterfaces = true }
        }
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Step(number: 1, text: "Settings → Wi-Fi → (i) → Configure Proxy → Manual")
                Step(number: 2, text: "Server \(model.lanProxyAddress?.split(separator: ":").first.map(String.init) ?? "—"), Port \(model.engine.boundPort ?? model.settings.port)")
                Step(number: 3, text: "Open \(pageURL) in Safari and tap the profile button")
                Step(number: 4, text: "Settings → Profile Downloaded → Install")
                Step(number: 5, text: "Settings → General → About → Certificate Trust Settings → enable Watcher Root CA")
            }
            if let directURL, let image = QRCode.image(for: directURL) {
                VStack {
                    Image(nsImage: image).interpolation(.none).resizable().frame(width: 140, height: 140).padding(8).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    Text("Scan to open the\ncertificate page").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Text(directURL).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        if !model.isRunning {
            Label("Start the proxy first — the page is served by Watcher.", systemImage: "play.circle").foregroundStyle(.secondary)
        }
        Button("Show Certificate File in Finder", systemImage: "folder") { model.revealCertificate() }
    }
}

private struct AndroidPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Heading(title: "Android", detail: "Works with emulators and USB devices that adb can see. Apps only trust user certificates if they opt in; browsers and debug builds do.")
        if model.devices.androidDevices.isEmpty, model.devices.isScanning {
            ProgressView("Looking for devices…").controlSize(.small).frame(maxWidth: .infinity, minHeight: 120)
        } else if model.devices.androidDevices.isEmpty {
            ContentUnavailableView("No Android device found", systemImage: "smartphone", description: Text("Start an emulator or connect a phone with USB debugging, and install adb (brew install android-platform-tools)."))
        } else {
            List(model.devices.androidDevices) { device in
                HStack {
                    VStack(alignment: .leading) { Text(device.model ?? device.serial); Text(device.isEmulator ? "Emulator · \(device.serial)" : device.serial).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Copy Certificate") { Task { await model.devices.pushCertificate(to: device) } }
                    Menu("Proxy") {
                        Button("Set Proxy to Watcher") { model.setAndroidProxy(device, enabled: true) }
                        Button("Clear Proxy") { model.setAndroidProxy(device, enabled: false) }
                    }.fixedSize()
                }
            }
            .frame(minHeight: 180)
        }
        Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.devices.refresh() } }.disabled(model.devices.isScanning)
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

#if DEBUG
    #Preview("iPhone setup") { DeviceSetupView(target: .iPhone).environment(AppModel(listening: false)) }
#endif
