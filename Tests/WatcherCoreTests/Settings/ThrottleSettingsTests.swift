import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ThrottleSettingsTests {
    @Test
    func customProfilesSaveReplaceDeleteAndKeepPresetsSafe() throws {
        var throttle = ThrottleSettings()
        throttle.profile = NetworkProfile(name: "Office VPN", downloadKbps: 2000, latencyMilliseconds: 80)
        throttle.saveCurrentProfile()
        throttle.profile.latencyMilliseconds = 120
        throttle.saveCurrentProfile()
        #expect(throttle.customProfiles.map(\.latencyMilliseconds) == [120])
        #expect(
            throttle.availableProfiles.contains { $0.name == "Office VPN" }
                && throttle.availableProfiles.contains { $0.name == "3G" }
        )

        throttle.profile = NetworkProfile(name: "3G", latencyMilliseconds: 1)
        throttle.saveCurrentProfile()
        #expect(throttle.customProfiles.count == 1, "presets must not be overwritten")

        throttle.deleteCustomProfile(named: "Office VPN")
        #expect(throttle.customProfiles.isEmpty)
        // Settings written before custom profiles existed still load.
        let old = try JSONDecoder().decode(ThrottleSettings.self, from: Data(#"{"isEnabled":true,"host":"a"}"#.utf8))
        #expect(old.isEnabled); #expect(old.customProfiles.isEmpty)
    }
}
