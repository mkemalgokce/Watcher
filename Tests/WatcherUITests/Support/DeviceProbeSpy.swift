import Foundation
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// A `DeviceProbe` that finds nothing, changes nothing and writes each action it was asked for into `calls`.
final class DeviceProbeSpy: Sendable {
    private let log = LockedBox<[String]>([])
    private let addresses: LockedBox<[String]>

    init(lan: [String] = []) {
        addresses = LockedBox(lan)
    }

    /// The addresses the Mac has on the local network, first preferred.
    var lan: [String] {
        get { addresses.value }
        set { addresses.mutate { $0 = newValue } }
    }

    var calls: [String] {
        log.value
    }

    var probe: DevicesViewModel.DeviceProbe {
        var probe = DevicesViewModel.DeviceProbe.none
        let (log, addresses) = (log, addresses)
        probe.lanAddresses = { addresses.value }
        probe.trustMac = { url in log.mutate { $0.append("trust \(url.lastPathComponent)") } }
        probe.removeMacTrust = { log.mutate { $0.append("untrust") } }
        probe.installOnSimulator = { url, udid in
            log.mutate { $0.append("simulator \(udid) \(url.lastPathComponent)") }
        }
        probe.setAndroidProxy = { device, endpoint in
            log.mutate { $0.append("proxy \(device.serial) \(endpoint ?? "off")") }
        }
        probe.pushCertificate = { device, url in
            log.mutate { $0.append("push \(device.serial) \(url.lastPathComponent)") }
        }
        return probe
    }
}
