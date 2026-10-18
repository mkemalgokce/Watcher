import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    /// The first-run sheet. The onboarding flag lives in the test runner's own UserDefaults domain, not Watcher's.
    @MainActor
    struct WelcomeTests {
        @Test
        func skippingClosesTheWelcomeWithoutCapturing() async throws {
            let skipping = AppModel(listening: false)
            skipping.onboardingDone = false
            skipping.sheet = .welcome
            try await withWindow(showing: WelcomeView().environment(skipping), width: 560, height: 460) { window in
                try await window.press("Skip for Now")
                #expect(skipping.onboardingDone)
                #expect(skipping.sheet == nil)
                #expect(!skipping.isRunning, "skipping does not start capturing")
            }
        }

        @Test
        func startCapturingRemembersTheChoiceAndStartsTheProxy() async throws {
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
