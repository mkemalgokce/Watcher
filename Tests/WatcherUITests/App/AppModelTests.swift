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
    func hidingAppleTrafficRefreshesTheList() throws {
        let model = try AppModel.test()
        model.settings.hideAppleTraffic = false
        [Flow.fixture(sequence: 1, host: "gateway.icloud.com", status: 200), .fixture(sequence: 2, status: 200)]
            .forEach { model.list.enqueue(.added($0)) }
        model.list.flushEvents()
        #expect(model.list.visibleFlows.count == 2)
        model.settings.hideAppleTraffic = true
        #expect(model.list.visibleFlows.map(\.sequence) == [2])
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
    func aStartupProblemIsShownAsAnErrorNoticeAtLaunch() throws {
        var dependencies = try AppDependencies.test()
        dependencies.startupProblem = "Cannot open Watcher's data in /x: nope."
        let model = AppModel(dependencies: dependencies)
        #expect(model.notices.notice?.message == "Cannot open Watcher's data in /x: nope.")
        #expect(model.notices.notice?.kind == .error)
    }

    @Test
    func noNoticeIsShownAtLaunchWhenNothingWentWrong() throws {
        #expect(try AppModel.test().notices.notice == nil)
    }

    @Test
    func theProxyDoesNotStartUntilRecordIsPressed() throws {
        let runner = ProxyRunnerStub()
        let model = try AppModel(dependencies: .test(runner: runner))
        model.onboardingDone = true
        #expect(runner.calls.isEmpty)
        #expect(!model.proxy.isRunning)
        #expect(model.statusLine == "Not recording · 0 requests")
    }

    @Test
    func finishingOnboardingRemembersItClosesTheSheetAndStartsRecording() async throws {
        let preferences = PreferencesFake()
        let runner = ProxyRunnerStub()
        let model = try AppModel(dependencies: .test(preferences: preferences, runner: runner))
        model.router.show(.welcome)
        model.finishOnboarding()
        #expect(preferences.onboardingDone)
        #expect(model.router.sheet == nil)
        #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })

        model.finishOnboarding()
        #expect(!model.proxy.isSwitchingProxy, "an already running proxy is not toggled off")
        #expect(runner.calls.count == 1)
    }

    @Test
    func quittingTheAppTurnsTheSystemProxyOff() async throws {
        let lifecycle = AppLifecycleSpy()
        let systemProxy = SystemProxySpy()
        let model = try AppModel(dependencies: .test(systemProxy: systemProxy, lifecycle: lifecycle))
        model.proxy.setSystemProxy(true)
        #expect(await eventually { model.proxy.systemProxyOn })
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
    func theProxyPortIsTheConfiguredOneUntilAPortIsBound() throws {
        let model = try AppModel.test()
        model.settings.port = 9123
        #expect(model.proxy.port == 9123)
    }

    @Test
    func statusLineUnderTheTitle() throws {
        let model = try AppModel.test()
        [Flow.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 500)]
            .forEach { model.list.enqueue(.added($0)) }
        model.list.flushEvents()
        #expect(model.statusLine == "Not recording · 2 requests")
        model.list.sidebar = .errors
        #expect(model.statusLine == "Not recording · 1 of 2 requests")
        model.proxy.proxyError = "port in use"
        #expect(model.statusLine == "Failed to start · see Settings")
    }

    @Test
    func deviceSetupHandsOutTheEnginesRootCertificate() throws {
        let model = try AppModel.test()
        #expect(model.devices.certificateURL == model.engine.authority.certificateURL)
    }

    @Test
    func aModelFollowingTheEngineIsFreedOnceNothingHoldsIt() throws {
        weak var model: AppModel?
        weak var list: FlowListViewModel?
        weak var breakpoints: BreakpointsViewModel?
        try {
            let following = try AppModel.test()
            following.observeEngine()
            model = following; list = following.list; breakpoints = following.breakpoints
        }()
        #expect(model == nil)
        #expect(list == nil, "the store observation must not keep the list alive")
        #expect(breakpoints == nil, "the breakpoint observation must not keep its view model alive")
    }
}
