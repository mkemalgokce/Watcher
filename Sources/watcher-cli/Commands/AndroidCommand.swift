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
