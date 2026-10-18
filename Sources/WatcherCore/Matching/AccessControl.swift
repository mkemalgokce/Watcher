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
        guard let address else { return false }
        if address == "127.0.0.1" || address == "::1" {
            return true
        }
        return !isEnabled || allowed.matches(address)
    }
}
