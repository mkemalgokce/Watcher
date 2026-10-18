import Foundation
import Testing
import WatcherTestSupport
@testable import WatcherUI

/// The preferences the app keeps between launches, their defaults and the menu toggles that flip them.
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

    @Test(arguments: BodyMode.allCases)
    func showingABodyModeStoresItsName(mode: BodyMode) {
        let preferences = PreferencesFake()
        preferences.showBody(mode)
        #expect(preferences.values["body.mode"] as? String == mode.rawValue)
    }

    @Test
    func theJSONFilterStartsOffAndToggles() {
        let preferences = PreferencesFake()
        preferences.toggleJSONFilter()
        #expect(preferences.values["body.jsonFilter"] as? Bool == true)
        preferences.toggleJSONFilter()
        #expect(preferences.values["body.jsonFilter"] as? Bool == false)
    }

    @Test
    func lineWrappingStartsOnAndToggles() {
        let preferences = PreferencesFake()
        preferences.toggleLineWrapping()
        #expect(preferences.values["body.wrap"] as? Bool == false)
        preferences.toggleLineWrapping()
        #expect(preferences.values["body.wrap"] as? Bool == true)
    }
}
