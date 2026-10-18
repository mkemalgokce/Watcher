import ArgumentParser
import Foundation
import WatcherCore

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
        try run(in: .live)
    }

    func run(in environment: CLIEnvironment) throws {
        let adb = environment.adb
        let devices = try AndroidDevice.list(run: adb)
        guard action != .list else { return Self.list(devices, to: environment.output) }
        let device = try chosenDevice(from: devices)
        switch action {
        case .list: break
        case .cert:
            try device.pushCertificate(environment.certificateAuthority().certificateURL, run: adb)
            environment.output(Self.certificateCopied)
        case .proxy:
            let lanAddress = environment.lanAddresses().first?.ip
            guard let endpoint = device.proxyEndpoint(port: port, lanAddress: lanAddress) else {
                throw ValidationError("No network address found for this Mac.")
            }
            try device.setProxy(endpoint, run: adb)
            environment.output("Proxy set to \(endpoint)")
        case .unproxy:
            try device.setProxy(nil, run: adb)
            environment.output("Proxy cleared")
        }
    }

    private static let certificateCopied = "Copied to Download/watcher-ca.cer. "
        + "On the device: Settings → Security → Install a certificate → CA certificate."

    private static func list(_ devices: [AndroidDevice], to output: (String) -> Void) {
        if devices.isEmpty {
            output("No Android device. Start an emulator or connect a phone with USB debugging.")
        }
        for device in devices {
            output("\(device.serial)\t\(device.isEmulator ? "emulator" : "device")\t\(device.model ?? "")")
        }
    }

    /// `--serial` names the device; without it there must be exactly one.
    private func chosenDevice(from devices: [AndroidDevice]) throws -> AndroidDevice {
        if let serial {
            guard let named = devices.first(where: { $0.serial == serial }) else { throw Self.unchosen(devices) }
            return named
        }
        guard devices.count == 1, let only = devices.first else { throw Self.unchosen(devices) }
        return only
    }

    private static func unchosen(_ devices: [AndroidDevice]) -> ValidationError {
        ValidationError(devices.isEmpty
            ? "No Android device is connected."
            : "Several devices are connected; pass --serial.")
    }
}
