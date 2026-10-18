import Foundation

/// Which LAN clients may use the proxy. Loopback is always allowed; with the switch on, other addresses must match a pattern (`192.168.1.*`).
public struct AccessControlSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var allowedAddresses: [String]
    public init(isEnabled: Bool = false, allowedAddresses: [String] = []) {
        self.isEnabled = isEnabled; self.allowedAddresses = allowedAddresses
    }

    /// Compiles the patterns once; checking a connection against the result builds no regular expressions.
    public func compile() -> AccessControl {
        AccessControl(self)
    }
}
