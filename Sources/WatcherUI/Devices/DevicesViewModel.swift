import Foundation
import Observation
import WatcherCore

/// What the device screens show and do: certificate trust on this Mac, simulators, Android devices, and the outcome
/// of the last action. System calls go through `DeviceProbe`, so previews and tests never touch the keychain, simctl or adb.
@MainActor @Observable
final class DevicesViewModel {
    /// Everything that reaches outside the app, replaceable in tests.
    struct DeviceProbe: Sendable {
        var simulators: @Sendable () -> [SimulatorCertificate.Simulator]
        var androidDevices: @Sendable () -> [AndroidDevice]
        var isMacTrusted: @Sendable () -> Bool

        static let live = DeviceProbe(
            simulators: { (try? SimulatorCertificate.simulators()) ?? [] },
            androidDevices: { (try? AndroidDevice.list()) ?? [] },
            isMacTrusted: { MacTrust().isInstalled() }
        )

        /// Previews and tests: nothing found, nothing trusted.
        static let none = DeviceProbe(simulators: { [] }, androidDevices: { [] }, isMacTrusted: { false })
    }

    /// The outcome of the last action, for the status line under each pane.
    enum Status: Equatable {
        case working(String)
        case done(String)
        case failed(String)

        var text: String {
            switch self { case let .working(t), let .done(t), let .failed(t): t }
        }
    }

    private(set) var simulators: [SimulatorCertificate.Simulator] = []
    private(set) var androidDevices: [AndroidDevice] = []
    private(set) var macTrusted = false
    internal(set) var status: Status?
    /// True while simctl/adb are being asked, so "nothing found" is not shown before the answer.
    internal(set) var isScanning = false

    @ObservationIgnored private let probe: DeviceProbe
    let certificateURL: URL

    init(probe: DeviceProbe, certificateURL: URL) {
        self.probe = probe
        self.certificateURL = certificateURL
    }

    /// Only the keychain check, for the first-run list: starting simctl and adb at launch woke the simulator service for nothing.
    func refreshMacTrust() async {
        let probe = probe
        macTrusted = await Task.detached { probe.isMacTrusted() }.value
    }

    /// Runs simctl, adb and the keychain check off the main thread; a scan already running is not started again.
    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        let probe = probe
        let (simulators, android, trusted) = await Task.detached { (probe.simulators(), probe.androidDevices(), probe.isMacTrusted()) }.value
        self.simulators = simulators; androidDevices = android; macTrusted = trusted
        isScanning = false
    }

    func trustOnMac() async {
        let url = certificateURL
        await run("Trusting the certificate on this Mac…", done: "Certificate trusted on this Mac.") { try MacTrust().install(certificate: url) }
    }

    func removeMacTrust() async {
        await run("Removing…", done: "Certificate removed from this Mac.") { try MacTrust().remove() }
    }

    func install(on simulator: SimulatorCertificate.Simulator) async {
        let url = certificateURL
        await run("Installing on \(simulator.name)…", done: "Installed on \(simulator.name). Restart apps that were already running.") {
            try SimulatorCertificate.install(certificate: url, device: simulator.udid)
        }
    }

    func setProxy(on device: AndroidDevice, enabled: Bool, port: Int, lanAddress: String?) async {
        let endpoint = enabled ? device.proxyEndpoint(port: port, lanAddress: lanAddress) : nil
        if enabled, endpoint == nil {
            status = .failed("No network address found for this Mac."); return
        }
        await run(enabled ? "Setting proxy…" : "Clearing proxy…", done: enabled ? "Proxy set on \(device.model ?? device.serial)." : "Proxy cleared.") {
            try device.setProxy(endpoint)
        }
    }

    func pushCertificate(to device: AndroidDevice) async {
        let url = certificateURL
        await run("Copying certificate…", done: "Copied to Downloads. Open Settings → Security → Install a certificate → CA certificate.") {
            try device.pushCertificate(url)
        }
    }

    /// Shows progress, runs `work` off the main thread, reports the outcome, then rescans so the panes show the new state.
    func run(_ start: String, done: String, _ work: @escaping @Sendable () throws -> Void) async {
        status = .working(start)
        let result = await Task.detached { Result { try work() } }.value
        switch result {
        case .success: status = .done(done)
        case let .failure(error): status = .failed("\(error)")
        }
        await refresh()
    }
}
