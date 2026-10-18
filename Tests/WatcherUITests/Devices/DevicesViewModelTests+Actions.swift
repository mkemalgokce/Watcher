import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension DevicesViewModelTests {
    /// Each button reaches the system only through the probe, with the right certificate, device and endpoint.
    @MainActor
    struct Actions {
        private static let certificate = URL(fileURLWithPath: "/fake-home/.watcher/watcher-ca.pem")
        private static let phone = AndroidDevice(serial: "R5", model: "Pixel 9", isEmulator: false)
        private let spy = DeviceProbeSpy()
        private func viewModel(lan: [String] = ["192.168.1.20"], port: Int = 9090) -> DevicesViewModel {
            spy.lan = lan
            return DevicesViewModel(probe: spy.probe, certificateURL: Self.certificate) { port }
        }

        @Test
        func trustingAndUntrustingTheMac() async {
            let devices = viewModel()
            await devices.trustOnMac()
            #expect(devices.status == .done("Certificate trusted on this Mac."))
            await devices.removeMacTrust()
            #expect(devices.status == .done("Certificate removed from this Mac."))
            #expect(spy.calls == ["trust watcher-ca.pem", "untrust"])
        }

        @Test
        func installingOnASimulatorUsesItsID() async {
            let simulator = SimulatorCertificate.Simulator(
                udid: "U1", name: "iPhone 17", runtime: "iOS 26", isBooted: true
            )
            let devices = viewModel()
            await devices.install(on: simulator)
            #expect(spy.calls == ["simulator U1 watcher-ca.pem"])
            #expect(devices.status == .done("Installed on iPhone 17. Restart apps that were already running."))
        }

        @Test
        func settingTheAndroidProxyPointsItAtThisMac() async {
            let devices = viewModel(port: 9123)
            await devices.setProxy(on: Self.phone, enabled: true)
            #expect(spy.calls == ["proxy R5 192.168.1.20:9123"])
            #expect(devices.status == .done("Proxy set on Pixel 9."))
            await devices.setProxy(on: Self.phone, enabled: false)
            #expect(spy.calls.last == "proxy R5 off")
            #expect(devices.status == .done("Proxy cleared."))
        }

        @Test
        func withoutANetworkAddressTheProxyIsNotSet() async {
            let devices = viewModel(lan: [])
            await devices.setProxy(on: Self.phone, enabled: true)
            #expect(spy.calls.isEmpty)
            #expect(devices.status == .failed("No network address found for this Mac."))
        }

        @Test
        func pushingTheCertificateToAPhone() async {
            let devices = viewModel()
            await devices.pushCertificate(to: Self.phone)
            #expect(spy.calls == ["push R5 watcher-ca.pem"])
        }

        @Test(arguments: [(["10.0.0.5", "192.168.1.2"], "10.0.0.5:8080"), ([], nil)])
        func theLANAddressUsesTheFirstInterfaceAndTheProxyPort(lan: [String], expected: String?) {
            #expect(viewModel(lan: lan, port: 8080).lanProxyAddress == expected)
        }

        @Test
        func thePreviewProbeChangesNothingOnTheSystem() async {
            let devices = DevicesViewModel(probe: .none, certificateURL: Self.certificate) { 9090 }
            await devices.trustOnMac()
            #expect(devices.status == .done("Certificate trusted on this Mac."))
            #expect(devices.lanProxyAddress == nil)
        }

        @Test
        func aScanAlreadyRunningIsNotStartedAgain() async {
            let scans = LockedBox(0)
            let blocked = DispatchSemaphore(value: 0)
            var probe = DevicesViewModel.DeviceProbe.none
            probe.simulators = {
                scans.mutate { $0 += 1 }
                if scans.value == 1 {
                    blocked.wait() // only the first scan is held, so a second one would show up instead of hanging
                }
                return []
            }
            let devices = DevicesViewModel(probe: probe, certificateURL: Self.certificate) { 9090 }
            let first = Task { await devices.refresh() }
            #expect(await eventually { scans.value == 1 })
            await devices.refresh()
            blocked.signal()
            await first.value
            #expect(scans.value == 1)
            #expect(!devices.isScanning)
        }

        @Test
        func trustingWhileAScanRunsShowsTheTrustWhenTheScanEnds() async {
            let trusted = LockedBox(false)
            let release = DispatchSemaphore(value: 0)
            let scanning = LockedBox(0)
            var probe = DevicesViewModel.DeviceProbe.none
            probe.isMacTrusted = {
                let value = trusted.value // read before the trust is installed
                scanning.mutate { $0 += 1 }
                if scanning.value == 1 {
                    release.wait()
                }
                return value
            }
            probe.trustMac = { _ in trusted.mutate { $0 = true } }
            let devices = DevicesViewModel(probe: probe, certificateURL: Self.certificate) { 9090 }
            let scan = Task { await devices.refresh() }
            #expect(await eventually { scanning.value == 1 })
            let trust = Task { await devices.trustOnMac() }
            #expect(await eventually { trusted.value })
            release.signal()
            await scan.value
            await trust.value
            #expect(devices.macTrusted)
            #expect(devices.status == .done("Certificate trusted on this Mac."))
        }

        @Test
        func theNetworkIsAskedOncePerRefreshNotOncePerRead() async {
            let asked = LockedBox(0)
            var probe = DevicesViewModel.DeviceProbe.none
            probe.lanAddresses = { asked.mutate { $0 += 1 }; return ["10.0.0.5"] }
            let devices = DevicesViewModel(probe: probe, certificateURL: Self.certificate) { 9090 }
            for _ in 0 ..< 5 {
                #expect(devices.lanProxyAddress == "10.0.0.5:9090")
            }
            #expect(asked.value == 1)
            await devices.refresh()
            #expect(devices.lanProxyAddress == "10.0.0.5:9090")
            #expect(asked.value == 2)
        }

        @Test(arguments: [
            (["10.0.0.5"], "10.0.0.5", "http://10.0.0.5:9090"), ([String](), "—", nil),
        ])
        func theDevicePageAndServerFollowTheNetworkAddress(lan: [String], server: String, url: String?) {
            let devices = viewModel(lan: lan)
            #expect(devices.serverHost == server)
            #expect(devices.certificateDirectURL == url)
            #expect(devices.certificatePageURL == (url ?? "http://watcher.cert"))
        }
    }
}
