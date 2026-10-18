import Testing
import WatcherTestSupport
@testable import WatcherUI

/// The preferences the app keeps between launches, and their defaults.
@Suite(.tags(.unit))
struct PreferencesWatcherTests {
    @Test
    func defaultsBeforeAnythingIsStored() {
        let preferences = PreferencesFake()
        #expect(!preferences.onboardingDone)
        #expect(preferences.websiteIconsEnabled)
    }

    @Test
    func onboardingAndIconsAreRemembered() {
        let preferences = PreferencesFake()
        preferences.onboardingDone = true
        preferences.websiteIconsEnabled = false
        #expect(preferences.values["onboarding.done"] as? Bool == true)
        #expect(preferences.values["icons.websites"] as? Bool == false)
        #expect(preferences.onboardingDone)
        #expect(!preferences.websiteIconsEnabled)
    }
}
