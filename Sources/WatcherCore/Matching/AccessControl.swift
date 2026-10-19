import Foundation

/// `AccessControlSettings` ready to check connections.
public struct AccessControl: Sendable {
    private let isEnabled: Bool
    private let allowed: HostList

    init(_ settings: AccessControlSettings) {
        isEnabled = settings.isEnabled
        allowed = HostList(settings.allowedAddresses)
    }

    public func allows(_ address: String?) -> Bool {
        guard let address = address.map(Self.unmapped) else { return false }
        if address == "127.0.0.1" || address == "::1" {
            return true
        }
        return !isEnabled || allowed.matches(address)
    }

    /// A dual-stack (`::`) listener reports IPv4 peers as `::ffff:a.b.c.d`; they are checked as that IPv4 address.
    static func unmapped(_ address: String) -> String {
        let prefix = "::ffff:"
        guard address.lowercased().hasPrefix(prefix), address.contains(".") else { return address }
        return String(address.dropFirst(prefix.count))
    }
}
