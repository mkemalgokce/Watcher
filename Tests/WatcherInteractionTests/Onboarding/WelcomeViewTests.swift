import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    /// The first-run sheet. The onboarding flag lives in the test runner's own UserDefaults domain, not Watcher's.
    @MainActor
    struct WelcomeViewTests {
        @Test
        func skippingClosesTheWelcomeWithoutCapturing() async throws {
            let skipping = try AppModel.test()
            skipping.onboardingDone = false
            skipping.router.sheet = .welcome
            try await withWindow(showing: WelcomeView().environment(skipping), width: 560, height: 460) { window in
                try await window.press("Skip for Now")
                #expect(skipping.onboardingDone)
                #expect(skipping.router.sheet == nil)
                #expect(!skipping.proxy.isRunning, "skipping does not start capturing")
            }
        }

        @Test
        func startCapturingRemembersTheChoiceAndStartsTheProxy() async throws {
            let starting = try AppModel.test()
            try starting.useFreePort(searchingFrom: 21000, fallback: 29998)
            starting.onboardingDone = false
            starting.router.sheet = .welcome
            try await withWindow(showing: WelcomeView().environment(starting), width: 560, height: 460) { window in
                try await window.press("Start Capturing")
                #expect(await eventually { starting.proxy.isRunning })
                #expect(starting.onboardingDone)
                #expect(starting.router.sheet == nil)
                #expect(starting.proxy.isRunning)
                starting.proxy.toggleRunning()
                _ = await eventually { !starting.proxy.isRunning }
            }
        }
    }
}
