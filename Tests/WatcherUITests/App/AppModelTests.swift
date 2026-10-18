import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// How the window's model turns store events into what the list, sidebar and status bar show.
@MainActor
@Suite(.serialized, .tags(.unit))
struct AppModelTests {
    @Test
    func hidingAppleTrafficRefreshesTheList() {
        let model = AppModel(listening: false)
        model.settings.hideAppleTraffic = false
        [Flow.fixture(sequence: 1, host: "gateway.icloud.com", status: 200), .fixture(sequence: 2, status: 200)]
            .forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        #expect(model.visibleFlows.count == 2)
        model.settings.hideAppleTraffic = true
        #expect(model.visibleFlows.map(\.sequence) == [2])
    }

    @Test
    func onboardingIsReadFromAndSavedToThePreferences() throws {
        let preferences = PreferencesFake(["onboarding.done": true])
        let model = try AppModel(dependencies: .test(preferences: preferences))
        #expect(model.onboardingDone)
        model.onboardingDone = false
        #expect(preferences.values["onboarding.done"] as? Bool == false)
    }

    @Test
    func finishingOnboardingRemembersItClosesTheSheetAndStartsRecording() async throws {
        let preferences = PreferencesFake()
        let runner = ProxyRunnerStub()
        let model = try AppModel(dependencies: .test(preferences: preferences, runner: runner))
        model.show(.welcome)
        model.finishOnboarding()
        #expect(preferences.onboardingDone)
        #expect(model.sheet == nil)
        #expect(await eventually { model.isRunning && !model.isSwitchingProxy })

        model.finishOnboarding()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(runner.calls.count == 1, "an already running proxy is not toggled off")
    }

    @Test
    func quittingTheAppTurnsTheSystemProxyOff() async throws {
        let lifecycle = AppLifecycleSpy()
        let systemProxy = SystemProxySpy()
        let model = try AppModel(dependencies: .test(systemProxy: systemProxy, lifecycle: lifecycle))
        model.setSystemProxy(true)
        #expect(await eventually { model.systemProxyOn })
        lifecycle.terminate()
        #expect(systemProxy.calls.last == "disable")
    }

    @Test
    func aProxyLeftOnByACrashIsRestoredWhenTheModelIsBuilt() throws {
        let systemProxy = SystemProxySpy(hasPendingRestore: true)
        _ = try AppModel(dependencies: .test(systemProxy: systemProxy))
        #expect(systemProxy.calls == ["disable"])
    }

    @Test
    func theProxyPortIsTheConfiguredOneUntilAPortIsBound() {
        let model = AppModel(listening: false)
        model.settings.port = 9123
        #expect(model.proxyPort == 9123)
    }

    @Test
    func statusLineUnderTheTitle() {
        let model = AppModel(listening: false)
        [Flow.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 500)]
            .forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        #expect(model.statusLine == "Not recording · 2 requests")
        model.sidebar = .errors
        #expect(model.statusLine == "Not recording · 1 of 2 requests")
        model.proxy.proxyError = "port in use"
        #expect(model.statusLine == "Failed to start · see Settings")
    }
}
