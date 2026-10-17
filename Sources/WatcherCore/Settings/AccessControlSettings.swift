import Foundation

/// Which LAN clients may use the proxy. Loopback is always allowed; with the switch on, other addresses must match a pattern (`192.168.1.*`).
public struct AccessControlSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var allowedAddresses: [String]
    public init(isEnabled: Bool = false, allowedAddresses: [String] = []) {
        self.isEnabled = isEnabled; self.allowedAddresses = allowedAddresses
    }

    public func allows(_ address: String?) -> Bool {
        guard let address else { return false }
        if address == "127.0.0.1" || address == "::1" {
            return true
        }
        return !isEnabled || HostList(allowedAddresses).matches(address)
    }
}
