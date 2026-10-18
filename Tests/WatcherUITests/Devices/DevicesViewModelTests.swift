import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Device setup: scanning, trust and the status of the last action, with the system calls replaced.
@MainActor
@Suite(.tags(.unit))
struct DevicesViewModelTests {
    private struct Boom: Error, CustomStringConvertible {
        var description: String {
            "adb: device offline"
        }
    }

    private static let certificateURL = URL(fileURLWithPath: "/tmp/ca.pem")

    private func viewModel(trusted: Bool = true) -> DevicesViewModel {
        let simulator = SimulatorCertificate.Simulator(udid: "U1", name: "iPhone 17", runtime: "iOS 26", isBooted: true)
        return DevicesViewModel(
            probe: .init(simulators: { [simulator] }, androidDevices: { [] }, isMacTrusted: { trusted }),
            certificateURL: Self.certificateURL
        )
    }

    @Test
    func refreshFillsTheListsAndEndsTheScan() async {
        let devices = viewModel()
        #expect(devices.simulators.isEmpty)
        await devices.refresh()
        #expect(!devices.isScanning)
        #expect(devices.simulators.map(\.name) == ["iPhone 17"])
        #expect(devices.androidDevices.isEmpty)
        #expect(devices.macTrusted)
    }

    @Test
    func refreshingMacTrustAloneDoesNotScanDevices() async {
        let devices = viewModel(trusted: false)
        await devices.refreshMacTrust()
        #expect(!devices.macTrusted)
        #expect(devices.simulators.isEmpty, "the cheap check does not run simctl")
    }

    @Test
    func actionsReportSuccessAndFailure() async {
        let devices = viewModel()
        await devices.run("Working…", done: "Done.") {}
        #expect(devices.status == .done("Done."))
        await devices.run("Working…", done: "Done.") { throw Boom() }
        #expect(devices.status == .failed("adb: device offline"))
        #expect(devices.simulators.count == 1, "the panes are rescanned after an action")
    }

    @Test
    func previewProbeFindsNothing() async {
        let devices = DevicesViewModel(probe: .none, certificateURL: Self.certificateURL)
        await devices.refresh()
        #expect(devices.simulators.isEmpty && devices.androidDevices.isEmpty && !devices.macTrusted)
    }
}
