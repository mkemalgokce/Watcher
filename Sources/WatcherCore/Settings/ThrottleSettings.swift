import Foundation

public struct ThrottleSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var profile: NetworkProfile
    /// `host` or `host:port`; no wildcards. Empty applies to all traffic.
    public var host: String
    /// Profiles the user saved under their own name; offered next to the built-in presets.
    public var customProfiles: [NetworkProfile]

    public init(isEnabled: Bool = false, profile: NetworkProfile = NetworkProfile.presets[0], host: String = "", customProfiles: [NetworkProfile] = []) {
        self.isEnabled = isEnabled; self.profile = profile; self.host = host; self.customProfiles = customProfiles
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, profile, host, customProfiles }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decode(.isEnabled, default: isEnabled)
        profile = try c.decode(.profile, default: profile)
        host = try c.decode(.host, default: host)
        customProfiles = try c.decode(.customProfiles, default: customProfiles)
    }

    /// Built-in presets followed by the saved ones.
    public var availableProfiles: [NetworkProfile] {
        NetworkProfile.presets + customProfiles
    }

    /// Saves `profile` under its name, replacing a saved profile with the same name; presets cannot be overwritten.
    public mutating func saveCurrentProfile() {
        guard !profile.name.isEmpty, !NetworkProfile.presets.contains(where: { $0.name == profile.name }) else { return }
        if let index = customProfiles.firstIndex(where: { $0.name == profile.name }) {
            customProfiles[index] = profile
        } else {
            customProfiles.append(profile)
        }
    }

    public mutating func deleteCustomProfile(named name: String) {
        customProfiles.removeAll { $0.name == name }
    }
}
