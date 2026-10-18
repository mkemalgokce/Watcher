import Foundation
import SnapshotTesting
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// Device setup: what the lists and addresses say with a phone network, without one and with devices to set up.
    @MainActor
    struct Devices {
        private func devices(lan: [String], trusted: Bool, found: Bool) -> DevicesViewModel {
            let simulators = found
                ? [SimulatorCertificate.Simulator(udid: "U1", name: "iPhone 17", runtime: "iOS 26", isBooted: true)]
                : []
            let androids = found ? [AndroidDevice(serial: "emulator-5554", model: "Pixel 9", isEmulator: true)] : []
            return DevicesViewModel(
                probe: .init(
                    simulators: { simulators }, androidDevices: { androids }, isMacTrusted: { trusted },
                    lanAddresses: { lan }
                ),
                certificateURL: URL(fileURLWithPath: "/fake/ca.pem")
            ) { 9090 }
        }

        private func describe(_ devices: DevicesViewModel) -> String {
            [
                "host: \(devices.serverHost)",
                "proxy address: \(devices.lanProxyAddress ?? "none")",
                "certificate page: \(devices.certificatePageURL)",
                "mac trusted: \(devices.macTrusted)",
                "simulators: \(devices.simulators.map { "\($0.name) (\($0.runtime))" })",
                "android: \(devices.androidDevices.map(\.serial))",
            ].joined(separator: "\n")
        }

        @Test
        func theThreeSetups() async {
            var texts: [String] = []
            for (lan, trusted, found) in [(["192.168.1.5"], true, true), ([String](), false, false)] {
                let model = devices(lan: lan, trusted: trusted, found: found)
                await model.refresh()
                texts.append(describe(model))
            }
            assertSnapshot(of: texts.joined(separator: "\n\n"), as: .lines)
        }
    }
}
