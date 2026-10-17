import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct WelcomeTests {
        /// First run: skipping closes the sheet without capturing; Start Capturing remembers the choice and starts the
        /// proxy. (UserDefaults here are the test runner's own domain, not Watcher's.)
        @Test
        func welcomeSkipAndStart() async throws {
            let skipping = AppModel(listening: false)
            skipping.onboardingDone = false
            skipping.sheet = .welcome
            try await withWindow(showing: WelcomeView().environment(skipping), width: 560, height: 460) { window in
                try await window.press("Skip for Now")
                #expect(skipping.onboardingDone)
                #expect(skipping.sheet == nil)
                #expect(!skipping.isRunning, "skipping does not start capturing")
            }

            let starting = AppModel(listening: false)
            try starting.useFreePort(searchingFrom: 21000, fallback: 29998)
            starting.onboardingDone = false
            starting.sheet = .welcome
            try await withWindow(showing: WelcomeView().environment(starting), width: 560, height: 460) { window in
                try await window.press("Start Capturing")
                #expect(await eventually { starting.isRunning })
                #expect(starting.onboardingDone)
                #expect(starting.sheet == nil)
                #expect(starting.isRunning)
                starting.toggleRunning()
                _ = await eventually { !starting.isRunning }
            }
        }
    }
}
