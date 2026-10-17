import ArgumentParser
import Foundation
import WatcherCore

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run the proxy and print traffic live.")

    @Option(help: "Port to listen on (default: from settings, 9090).") var port: Int?
    @Flag(help: "Tunnel HTTPS untouched instead of decrypting it.") var noDecrypt = false
    @Option(help: "Write the session to this HAR file when you press Ctrl-C.") var har: String?
    @Option(help: "Write the session to this CSV file when you press Ctrl-C.") var csv: String?
    @Flag(help: "Point the macOS system proxy at Watcher while running.") var systemProxy = false

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let engine = try WatcherEngine()
        engine.onLog = { print("[log] \($0)") }
        let bound = try await engine.start(port: port)
        print("Watcher listening on 127.0.0.1:\(bound)")
        if engine.settings.value.listenOnAllInterfaces {
            for address in LocalNetwork.ipv4Addresses() {
                print("  reachable from devices at \(address.ip):\(bound)  (\(address.interface))")
            }
        }

        if noDecrypt {
            var settings = engine.settings.value
            settings.sslProxying.include = []
            await engine.apply(settings)
        }
        if systemProxy {
            try SystemProxy.enable(port: bound)
        }

        // Headless sessions cannot edit a held message, so breakpoints just continue unchanged.
        let breakpointTask = Task {
            for await _ in engine.breakpoints.changes() {
                for hit in engine.breakpoints.pending {
                    print("[breakpoint] \(hit.phase.rawValue) \(hit.request.method) \(hit.request.url) (continued; use the app to edit)")
                    engine.breakpoints.resolve(hit.id, with: .proceed(request: hit.request, response: hit.response))
                }
            }
        }

        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT)
        signal(SIGINT, SIG_IGN)
        interrupt.setEventHandler {
            Task {
                if systemProxy {
                    try? SystemProxy.disable()
                }
                if let har {
                    try? HAR.export(engine.store.all).write(to: URL(fileURLWithPath: (har as NSString).expandingTildeInPath)); print("Saved \(har)")
                }
                if let csv {
                    try? CSVExporter.export(engine.store.all).write(to: URL(fileURLWithPath: (csv as NSString).expandingTildeInPath)); print("Saved \(csv)")
                }
                breakpointTask.cancel()
                try? await engine.stop()
                Foundation.exit(0)
            }
        }
        interrupt.resume()

        var printed = Set<Flow.ID>()
        for await event in engine.store.events() {
            // Flows update several times (streamed headers, WebSocket messages); print each once it has finished.
            guard case let .updated(flow) = event, flow.state != .pending, let response = flow.response, printed.insert(flow.id).inserted else { continue }
            let milliseconds = Int((flow.duration ?? 0) * 1000)
            let tools = flow.appliedTools.isEmpty ? "" : "  [\(flow.appliedTools.joined(separator: ", "))]"
            print("\(flow.sequence)  \(response.status)  \(flow.request.method)  \(flow.request.url)  \(milliseconds)ms\(tools)")
        }
    }
}

struct Cert: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the root certificate path; trust it to decrypt HTTPS.")

    func run() throws {
        _ = try CertificateAuthority(directory: WatcherPaths.supportDirectory)
        print(WatcherPaths.supportDirectory.appendingPathComponent("watcher-ca.pem").path)
    }
}

struct SimulatorCert: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install-simulator-cert", abstract: "Trust the Watcher root certificate in an iOS Simulator.")

    @Option(help: "`booted`, `all` or a simulator UDID.") var device = "booted"

    func run() throws {
        let authority = try CertificateAuthority(directory: WatcherPaths.supportDirectory)
        _ = authority
        try SimulatorCertificate.install(certificate: WatcherPaths.supportDirectory.appendingPathComponent("watcher-ca.pem"), device: device)
        print("Installed in \(device)")
    }
}

struct AndroidCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "android",
        abstract: "List Android devices, copy the root certificate to one, or point its proxy at Watcher."
    )

    enum Action: String, ExpressibleByArgument { case list, cert, proxy, unproxy }

    @Argument(help: "list | cert (copy to Downloads) | proxy (set) | unproxy (clear)") var action: Action = .list
    @Option(help: "adb serial; defaults to the only connected device.") var serial: String?
    @Option(help: "Watcher port the device should use.") var port = 9090

    func run() throws {
        let devices = try AndroidDevice.list()
        if action == .list {
            if devices.isEmpty {
                print("No Android device. Start an emulator or connect a phone with USB debugging.")
            }
            for device in devices {
                print("\(device.serial)\t\(device.isEmulator ? "emulator" : "device")\t\(device.model ?? "")")
            }
            return
        }
        guard let device = serial.map({ wanted in devices.first { $0.serial == wanted } }) ?? (devices.count == 1 ? devices.first : nil) else {
            throw ValidationError(devices.isEmpty ? "No Android device is connected." : "Several devices are connected; pass --serial.")
        }
        switch action {
        case .list: break
        case .cert:
            _ = try CertificateAuthority(directory: WatcherPaths.supportDirectory)
            try device.pushCertificate(WatcherPaths.supportDirectory.appendingPathComponent("watcher-ca.pem"))
            print("Copied to Download/watcher-ca.cer. On the device: Settings → Security → Install a certificate → CA certificate.")
        case .proxy:
            guard let endpoint = device.proxyEndpoint(port: port, lanAddress: LocalNetwork.ipv4Addresses().first?.ip) else {
                throw ValidationError("No network address found for this Mac.")
            }
            try device.setProxy(endpoint)
            print("Proxy set to \(endpoint)")
        case .unproxy:
            try device.setProxy(nil)
            print("Proxy cleared")
        }
    }
}

struct SystemProxyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "proxy", abstract: "Turn the macOS system HTTP(S) proxy on or off.")

    enum State: String, ExpressibleByArgument { case on, off }

    @Argument var state: State
    @Option var port = 9090

    func run() throws {
        switch state {
        case .on: try SystemProxy.enable(port: port)
        case .off: try SystemProxy.disable()
        }
        print("System proxy \(state.rawValue)")
    }
}
