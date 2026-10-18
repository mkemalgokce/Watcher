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
        /// This Mac's IPv4 addresses on the local network, the first one preferred.
        var lanAddresses: @Sendable () -> [String] = { [] }
        var trustMac: @Sendable (_ certificate: URL) throws -> Void = { _ in }
        var removeMacTrust: @Sendable () throws -> Void = {}
        var installOnSimulator: @Sendable (_ certificate: URL, _ udid: String) throws -> Void = { _, _ in }
        var setAndroidProxy: @Sendable (AndroidDevice, _ endpoint: String?) throws -> Void = { _, _ in }
        var pushCertificate: @Sendable (AndroidDevice, _ certificate: URL) throws -> Void = { _, _ in }

        static let live = DeviceProbe(
            simulators: { (try? SimulatorCertificate.simulators()) ?? [] },
            androidDevices: { (try? AndroidDevice.list()) ?? [] },
            isMacTrusted: { MacTrust().isInstalled() },
            lanAddresses: { LocalNetwork.ipv4Addresses().map(\.ip) },
            trustMac: { try MacTrust().install(certificate: $0) },
            removeMacTrust: { try MacTrust().remove() },
            installOnSimulator: { try SimulatorCertificate.install(certificate: $0, device: $1) },
            setAndroidProxy: { try $0.setProxy($1) },
            pushCertificate: { try $0.pushCertificate($1) }
        )

        /// Previews and tests: nothing found, nothing trusted, and actions that change nothing.
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
    @ObservationIgnored private let port: () -> Int
    let certificateURL: URL

    init(probe: DeviceProbe, certificateURL: URL, port: @escaping () -> Int) {
        self.probe = probe
        self.certificateURL = certificateURL
        self.port = port
    }

    /// Read once per scan: asking the network interfaces on every redraw would be wasted work on the main thread.
    @ObservationIgnored private var cachedLANAddress: String??
    @ObservationIgnored private var scan: Task<Void, Never>?

    /// The Mac's address a phone on the same network should use, without the port.
    private var lanAddress: String? {
        if let cachedLANAddress {
            return cachedLANAddress
        }
        let address = probe.lanAddresses().first
        cachedLANAddress = .some(address)
        return address
    }

    /// Address a phone on the same network should use as its proxy.
    var lanProxyAddress: String? {
        lanAddress.map { "\($0):\(port())" }
    }

    /// The host to type into a phone's proxy settings.
    var serverHost: String {
        lanAddress ?? "—"
    }

    /// The certificate page reached by address, for a phone that is not yet using the proxy.
    var certificateDirectURL: String? {
        lanProxyAddress.map { "http://\($0)" }
    }

    /// Where a phone downloads the certificate: the direct address when known, else Watcher's own host name.
    var certificatePageURL: String {
        certificateDirectURL ?? "http://watcher.cert"
    }

    /// Only the keychain check, for the first-run list: starting simctl and adb at launch woke the simulator service for nothing.
    func refreshMacTrust() async {
        let probe = probe
        macTrusted = await Task.detached { probe.isMacTrusted() }.value
    }

    /// Runs simctl, adb and the keychain check off the main thread; a scan already running is not started again.
    func refresh() async {
        guard scan == nil else { return }
        isScanning = true
        cachedLANAddress = nil
        let probe = probe
        let task = Task {
            let found = await Task.detached { (probe.simulators(), probe.androidDevices(), probe.isMacTrusted()) }.value
            (simulators, androidDevices, macTrusted) = found
            isScanning = false
            scan = nil
        }
        scan = task
        await task.value
    }

    /// A scan that began before an action saw the system as it was; wait for it, then look again.
    private func rescan() async {
        await scan?.value
        await refresh()
    }

    func trustOnMac() async {
        let url = certificateURL
        let trust = probe.trustMac
        await run("Trusting the certificate on this Mac…", done: "Certificate trusted on this Mac.") { try trust(url) }
    }

    func removeMacTrust() async {
        let remove = probe.removeMacTrust
        await run("Removing…", done: "Certificate removed from this Mac.") { try remove() }
    }

    func install(on simulator: SimulatorCertificate.Simulator) async {
        let url = certificateURL, install = probe.installOnSimulator
        let done = "Installed on \(simulator.name). Restart apps that were already running."
        await run("Installing on \(simulator.name)…", done: done) { try install(url, simulator.udid) }
    }

    func setProxy(on device: AndroidDevice, enabled: Bool) async {
        let endpoint = enabled ? device.proxyEndpoint(port: port(), lanAddress: lanAddress) : nil
        if enabled, endpoint == nil {
            status = .failed("No network address found for this Mac."); return
        }
        let apply = probe.setAndroidProxy
        let done = enabled ? "Proxy set on \(device.model ?? device.serial)." : "Proxy cleared."
        await run(enabled ? "Setting proxy…" : "Clearing proxy…", done: done) { try apply(device, endpoint) }
    }

    func pushCertificate(to device: AndroidDevice) async {
        let url = certificateURL, push = probe.pushCertificate
        let done = "Copied to Downloads. Open Settings → Security → Install a certificate → CA certificate."
        await run("Copying certificate…", done: done) { try push(device, url) }
    }

    /// Shows progress, runs `work` off the main thread, reports the outcome, then rescans so the panes show the new state.
    func run(_ start: String, done: String, _ work: @escaping @Sendable () throws -> Void) async {
        status = .working(start)
        let result = await Task.detached { Result { try work() } }.value
        switch result {
        case .success: status = .done(done)
        case let .failure(error): status = .failed("\(error)")
        }
        await rescan()
    }
}
