import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ProxyControllerTests {
    /// Switches that fail, repeat or overlap.
    @MainActor
    struct Edges {
        private let log = LockedBox<[String]>([])
        /// The proxy and system-proxy calls in order, without the recording switches that ProxyControllerTests covers.
        private var systemCalls: [String] {
            log.value.filter { !$0.hasPrefix("recording") }
        }

        private let notices = NoticeCenter.silent()

        private func controller(
            systemProxy: SystemProxySpy, autoSystemProxy: Bool = false
        ) -> (ProxyController, ProxyRunnerStub) {
            let runner = ProxyRunnerStub(log: log)
            var settings = WatcherSettings()
            settings.autoSystemProxy = autoSystemProxy
            let frozen = settings
            return (ProxyController(runner: runner, systemProxy: systemProxy, notices: notices) { frozen }, runner)
        }

        @Test
        func aStartWhoseSystemProxySwitchFailsKeepsRecordingAndSaysWhatFailed() async {
            let systemProxy = SystemProxySpy(log: log)
            systemProxy.failFromNowOn()
            let (proxy, _) = controller(systemProxy: systemProxy, autoSystemProxy: true)
            proxy.toggleRunning()
            #expect(await eventually { notices.notice?.kind == .error })
            #expect(notices.notice?.message.hasPrefix("Cannot change the system proxy") == true)
            #expect(proxy.isRunning)
            #expect(!proxy.systemProxyOn)
            #expect(proxy.state == .running)
        }

        @Test
        func switchingTheSystemProxyOffWhileItIsOffLeavesItOffAndSaysSo() async {
            let systemProxy = SystemProxySpy(log: log)
            let (proxy, _) = controller(systemProxy: systemProxy)
            proxy.setSystemProxy(false)
            let message = "System proxy off. Your original settings are back."
            #expect(await eventually { notices.notice?.message == message })
            #expect(!proxy.systemProxyOn)
        }

        @Test
        func aFailingRestoreAtLaunchOrQuitIsSwallowed() async {
            let systemProxy = SystemProxySpy(hasPendingRestore: true, log: log)
            let (proxy, _) = controller(systemProxy: systemProxy)
            proxy.setSystemProxy(true)
            #expect(await eventually { proxy.systemProxyOn })
            systemProxy.failFromNowOn()
            proxy.restoreLeftoverSystemProxy()
            proxy.applicationWillTerminate()
            #expect(proxy.systemProxyOn, "nothing is assumed about a switch that failed")
            #expect(notices.notice?.kind == .success)
        }

        @Test
        func pausingWaitsForTheSystemProxySwitchThatRecordStarted() async {
            let gate = DispatchSemaphore(value: 0)
            let systemProxy = SystemProxySpy(log: log, enableGate: gate)
            let (proxy, _) = controller(systemProxy: systemProxy, autoSystemProxy: true)
            proxy.toggleRunning()
            #expect(await eventually { proxy.isRunning && !proxy.isSwitchingProxy })
            proxy.toggleRunning()
            #expect(await eventually { systemProxy.enableCallsStarted == 1 })
            #expect(log.value == ["recording on", "start 9090", "recording off"], "recording stops at the click")
            #expect(!log.value.contains("disable"), "but the enable is still held, so the proxy has not stopped")
            gate.signal()
            #expect(await eventually { systemCalls == ["start 9090", "enable 9123", "disable", "stop"] })
            #expect(await eventually { !proxy.isSwitchingProxy })
            #expect(!proxy.systemProxyOn)
        }

        @Test
        func twoQuickClicksOnTheSystemProxyEndInTheStateOfTheLastClick() async {
            let gate = DispatchSemaphore(value: 0)
            let systemProxy = SystemProxySpy(log: log, enableGate: gate)
            let (proxy, _) = controller(systemProxy: systemProxy)
            proxy.toggleSystemProxy()
            #expect(await eventually { systemProxy.enableCallsStarted == 1 })
            proxy.toggleSystemProxy()
            gate.signal()
            #expect(await eventually { log.value == ["enable 9090", "disable"] })
            let isOff = { notices.notice?.message.hasPrefix("System proxy off") == true }
            #expect(await eventually { !proxy.systemProxyOn && isOff() })
        }

        @Test
        func aSystemProxyClickQueuedBeforePauseIsUndoneBeforeTheProxyStops() async {
            let systemProxy = SystemProxySpy(log: log)
            let (proxy, _) = controller(systemProxy: systemProxy)
            proxy.toggleRunning()
            #expect(await eventually { proxy.isRunning && !proxy.isSwitchingProxy })
            proxy.toggleRunning()
            proxy.toggleSystemProxy()
            #expect(await eventually { systemCalls == ["start 9090", "enable 9123", "disable", "stop"] })
            #expect(await eventually { !proxy.isSwitchingProxy })
            #expect(!proxy.systemProxyOn)
            #expect(!proxy.isRunning)
        }

        @Test
        func twoQuickSetsOfTheOppositeOfTheTargetEndInTheStateOfTheLastOne() async {
            let gate = DispatchSemaphore(value: 0)
            let systemProxy = SystemProxySpy(log: log, enableGate: gate)
            let (proxy, _) = controller(systemProxy: systemProxy)
            proxy.setSystemProxy(!proxy.systemProxyTarget)
            #expect(await eventually { systemProxy.enableCallsStarted == 1 })
            proxy.setSystemProxy(!proxy.systemProxyTarget)
            gate.signal()
            #expect(await eventually { log.value == ["enable 9090", "disable"] })
            #expect(await eventually { !proxy.systemProxyOn && !proxy.systemProxyTarget })
        }

        @Test
        func theSystemProxyCanBeSwitchedOnlyWhileRecordingAndNotMidSwitch() async {
            let (proxy, _) = controller(systemProxy: SystemProxySpy(log: log))
            #expect(!proxy.canSwitchSystemProxy)
            proxy.toggleRunning()
            #expect(!proxy.canSwitchSystemProxy)
            #expect(await eventually { proxy.isRunning && !proxy.isSwitchingProxy })
            #expect(proxy.canSwitchSystemProxy)
            proxy.toggleRunning()
            #expect(!proxy.canSwitchSystemProxy)
            #expect(await eventually { !proxy.isSwitchingProxy })
            #expect(!proxy.canSwitchSystemProxy)
        }

        @Test
        func aClickAfterAFailedSwitchTriesTheSameSwitchAgain() async {
            let systemProxy = SystemProxySpy(log: log)
            systemProxy.failFromNowOn()
            let (proxy, _) = controller(systemProxy: systemProxy)
            proxy.toggleSystemProxy()
            #expect(await eventually { notices.notice?.kind == .error })
            proxy.toggleSystemProxy()
            #expect(await eventually { systemProxy.enableCallsStarted == 2 })
        }

        @Test
        func systemProxySwitchesRunInTheOrderTheyWereAsked() async {
            let gate = DispatchSemaphore(value: 0)
            let systemProxy = SystemProxySpy(log: log, enableGate: gate)
            let (proxy, _) = controller(systemProxy: systemProxy)
            proxy.setSystemProxy(true)
            #expect(await eventually { systemProxy.enableCallsStarted == 1 })
            proxy.setSystemProxy(false)
            #expect(await !eventually(timeout: 0.3) { log.value.contains("disable") }, "off waits for the switch on")
            gate.signal()
            #expect(await eventually { log.value == ["enable 9090", "disable"] })
            #expect(await eventually { !proxy.isSwitchingProxy && !proxy.systemProxyOn })
        }

        @Test
        func theProxyReportsStoppingWhilePauseWaitsForASystemProxySwitch() async {
            let gate = DispatchSemaphore(value: 0)
            let systemProxy = SystemProxySpy(log: log, enableGate: gate)
            let (proxy, _) = controller(systemProxy: systemProxy, autoSystemProxy: true)
            proxy.toggleRunning()
            #expect(await eventually { proxy.isRunning && !proxy.isSwitchingProxy })
            proxy.toggleRunning()
            #expect(proxy.status(listing: "0 requests") == "Stopping…")
            gate.signal()
            #expect(await eventually { !proxy.isSwitchingProxy })
            #expect(proxy.status(listing: "0 requests") == "Not recording · 0 requests")
        }

        @Test
        func aFailedStartMirrorsTheRunnerThatIsStillListening() async {
            let (proxy, runner) = controller(systemProxy: SystemProxySpy(log: log))
            runner.failStarting(stillRunning: true)
            proxy.toggleRunning()
            #expect(await eventually { proxy.proxyError != nil && !proxy.isSwitchingProxy })
            #expect(proxy.isRunning)
            #expect(proxy.state == .failed)
        }
    }
}
